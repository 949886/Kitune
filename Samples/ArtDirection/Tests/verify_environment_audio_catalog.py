"""Independent struct-based oracle for every decoded environment audio object.

No generated type tree is used here. Fail on an unexpected UnityEvent layout,
truncation, trailing bytes, mismatched header, changed source or altered catalog.
Run with the repository's existing UnityPy dependencies on PYTHONPATH.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import UnityPy


class Reader:
    def __init__(self, data):
        self.data, self.offset = data, 0

    def unpack(self, fmt):
        value = struct.unpack_from('<' + fmt, self.data, self.offset)
        self.offset += struct.calcsize('<' + fmt)
        return value[0] if len(value) == 1 else value

    def align(self):
        end = (self.offset + 3) & ~3
        assert not any(self.data[self.offset:end]), 'unexpected padding'
        self.offset = end

    def string(self):
        size = self.unpack('i')
        assert 0 <= size <= len(self.data) - self.offset
        value = self.data[self.offset:self.offset + size].decode('utf8')
        self.offset += size
        self.align()
        return value

    def pointer(self):
        file_id, path_id = self.unpack('iq')
        return {'m_FileID': file_id, 'm_PathID': path_id}

    def header(self):
        fields = {'m_GameObject': self.pointer(), 'm_Enabled': self.unpack('B')}
        self.align()
        fields['m_Script'] = self.pointer()
        fields['m_Name'] = self.string()
        return fields

    def event(self):
        calls = []
        count = self.unpack('i')
        assert 0 <= count < 10000
        for _ in range(count):
            call = {'m_Target': self.pointer(), 'm_TargetAssemblyTypeName': self.string(),
                    'm_MethodName': self.string(), 'm_Mode': self.unpack('i')}
            call['m_Arguments'] = {'m_ObjectArgument': self.pointer(),
                'm_ObjectArgumentAssemblyTypeName': self.string(), 'm_IntArgument': self.unpack('i'),
                'm_FloatArgument': self.unpack('f'), 'm_StringArgument': self.string(), 'm_BoolArgument': self.unpack('B')}
            self.align()
            call['m_CallState'] = self.unpack('i')
            calls.append(call)
        return {'m_PersistentCalls': {'m_Calls': calls}}

    def guid(self):
        return {'Guid': {f'Data{i}': self.unpack('i') for i in range(1, 5)}}

    def dictionary(self, value):
        count = self.unpack('i')
        assert 0 <= count < 10000
        keys = [self.string() for _ in range(count)]
        count = self.unpack('i')
        assert 0 <= count < 10000
        return {'keys': keys, 'values': [value() for _ in range(count)]}

    def read(self, kind):
        fields = self.header()
        if kind == 'BGMProfile':
            fields['bgmInfo'] = self.dictionary(self.guid)
        else:
            fields['triggerLayer'] = {'m_Bits': self.unpack('I')}
            fields['once'] = self.unpack('B'); self.align()
            fields['IsFirstActivated'] = self.unpack('B'); self.align()
            for key in ['enterEvent', 'exitEvent', 'loadEvent']: fields[key] = self.event()
            fields['id'] = self.string()
            if kind == 'BGMParameterTrigger': fields['Emitter'] = self.guid()
            fields['parameters'] = self.dictionary(lambda: self.unpack('f'))
        assert self.offset == len(self.data), (self.offset, len(self.data))
        return fields


def verify(source):
    root = Path(__file__).resolve().parents[3]
    document = json.loads((root / 'Samples/ArtDirection/Original/INARI/environment_audio.json').read_text(encoding='utf8'))
    for name, digest in document['source_sha256'].items():
        assert hashlib.sha256((source / name).read_bytes()).hexdigest() == digest, name
    for name, digest in document['input_sha256'].items():
        assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
    for name, digest in document['behavior_sha256'].items():
        assert hashlib.sha256((root / 'tmp/art-direction/decompiled' / name).read_bytes()).hexdigest() == digest, name
    checked, assignments = 0, 0
    for file, records in document['levels'].items():
        env = UnityPy.load(str(source / file))
        objects = {o.path_id: o for o in env.objects if o.assets_file.name == file}
        for record in records:
            raw = objects[int(record['source']['component_id'])].get_raw_data()
            assert hashlib.sha256(raw).hexdigest() == record['audit']['raw_sha256']
            assert len(raw) == record['audit']['bytes'] and record['audit']['roundtrip_equal']
            assert Reader(raw).read(record['source']['type']) == record['fields']
            # The source dictionary keeps the first occurrence and stops at min
            # length. Derive it independently without importing the decoder.
            fields = record['fields']['parameters']
            expected = {}
            for index in range(min(len(fields['keys']), len(fields['values']))):
                expected.setdefault(fields['keys'][index], fields['values'][index])
            assert expected == record['parameters']
            event = document['events'][record['resolved_event_guid']]
            for assignment in record['assignments']:
                assert assignment['set_result'] == assignment['read_result'] == 0
                assert assignment['value'] == assignment['requested']
                description = event['parameters'][assignment['name']]
                assert description['minimum'] <= assignment['value'] <= description['maximum']
                assignments += 1
            # Reject truncation and ignored suffixes, not only well-formed files.
            for corrupt in [raw[:-1], raw + b'\0']:
                try: Reader(corrupt).read(record['source']['type'])
                except (AssertionError, struct.error): pass
                else: raise AssertionError('Accepted malformed serialized record')
            checked += 1
    profile = document['profile']
    env = UnityPy.load(str(source / profile['file']))
    obj = next(o for o in env.objects if o.assets_file.name == profile['file'] and o.path_id == profile['id'])
    assert Reader(obj.get_raw_data()).read('BGMProfile') == profile['fields']
    assert checked == 224 and assignments == 2760 and len(document['events']) == 12
    assert len(document['scanned_headers']) == 60
    print('ENVIRONMENT_AUDIO_INDEPENDENT_PASS', checked, 'triggers + profile;', assignments, 'native FMOD assignments')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    verify(parser.parse_args().source)
