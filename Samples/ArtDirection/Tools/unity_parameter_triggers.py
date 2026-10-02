"""Read shipped string/float dictionaries without changing Unity assets.

TypeTreeGenerator labels List<string> as a scalar string, and omits alignment
after MonoBehaviour.m_Enabled. Patch a private tree before constructing nodes:
UnityPyBoost caches its type dispatch, so mutating an existing node is unsafe.
Every decoded object must reserialize byte-for-byte and match its native header.
"""
import hashlib
import struct
import uuid
from UnityPy.helpers.TypeTreeNode import TypeTreeNode
from UnityPy.helpers import TypeTreeHelper
from UnityPy.streams import EndianBinaryWriter

TYPES = {'AmbientParameterTrigger', 'BGMParameterTrigger', 'ReverbParameterTrigger'}


def runtime_dictionary(keys, values):
    """SerializableDictionary.OnAfterDeserialize: zip to min, first key wins."""
    result = {}
    for key, value in zip(keys, values):
        if key is not None and key not in result:
            result[key] = value
    return result


def guid_string(value):
    return str(uuid.UUID(bytes_le=struct.pack('<4I', *(int(value[f'Data{i}']) & 0xffffffff for i in range(1, 5)))))


def decode(obj, additional_types=()):
    header = obj.parse_monobehaviour_head()
    name = header.m_Script.read().m_ClassName
    assert name in TYPES or name == 'BGMProfile' or name in additional_types, name
    # Strip children when flattening, otherwise from_list would append them twice.
    nodes = [{k: v for k, v in n.items() if k != 'm_Children'} for n in obj._get_typetree_node().to_dict_list()]
    patched = []
    for i, node in enumerate(nodes):
        if node['m_Name'] == 'keys':
            assert node['m_Type'] in ('string', 'vector')
            assert nodes[i + 1]['m_Type'] == 'Array' and nodes[i + 3]['m_Type'] == 'string'
            node['m_Type'] = 'vector'
            patched.append('keys:List<string>')
        elif node['m_Name'] == 'm_Enabled':
            node['m_MetaFlag'] = int(node.get('m_MetaFlag') or 0) | 0x4000
            patched.append('m_Enabled:align4')
    assert 'm_Enabled:align4' in patched, (name, patched)
    if name in TYPES or name == 'BGMProfile':
        assert len(patched) == 2, (name, patched)
    tree = TypeTreeNode.from_list(nodes)
    fields = obj.read_typetree(nodes=tree, check_read=True)
    assert fields['m_GameObject']['m_PathID'] == header.m_GameObject.path_id
    assert fields['m_Script'] == {'m_FileID': header.m_Script.file_id, 'm_PathID': header.m_Script.path_id}
    assert fields['m_Enabled'] == header.m_Enabled and fields['m_Name'] == header.m_Name
    writer = EndianBinaryWriter(endian=obj.reader.endian)
    TypeTreeHelper.write_typetree(fields, tree, writer, obj.assets_file)
    raw = obj.get_raw_data()
    assert writer.bytes == raw, (obj.assets_file.name, obj.path_id, 'binary roundtrip')
    return fields, {'bytes': len(raw), 'raw_sha256': hashlib.sha256(raw).hexdigest(),
                    'repairs': patched, 'roundtrip_equal': True}
