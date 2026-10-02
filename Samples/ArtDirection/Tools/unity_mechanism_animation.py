"""Export the small trigger-driven controllers used by scene mechanisms.

Keep transition evidence as well as visual tracks. These controllers have no
blend trees or parameter-dependent transitions; fail rather than silently choose
a branch if a future scene introduces one.
"""

from unity_scene_animation import animator_tracks, target_paths


def controller(importer, obj, gos, poses, by_go):
    if obj is None:
        return {}
    animator = obj.read()
    raw = animator.m_Controller.read_typetree()
    names = dict(raw["m_TOS"])
    machine = raw["m_Controller"]["m_StateMachineArray"][0]["data"]
    paths = target_paths(animator.m_GameObject.path_id, gos, poses, by_go)
    states, triggers = [], {}
    for index, wrapped in enumerate(machine["m_StateConstantArray"]):
        state = wrapped["data"]
        tracks = animator_tracks(importer, obj, paths, poses, by_go, selected_state=index)
        transitions = [t["data"] for t in state["m_TransitionConstantArray"]]
        assert all(t["m_HasExitTime"] and not t["m_ConditionConstantArray"] for t in transitions)
        assert len(transitions) <= 1
        states.append({"name": names[state["m_NameID"]], "tracks": tracks,
                       "length": max((t["length"] for t in tracks), default=0),
                       "transitions": transitions})
    for wrapped in machine["m_AnyStateTransitionConstantArray"]:
        transition = wrapped["data"]
        conditions = transition["m_ConditionConstantArray"]
        assert len(conditions) == 1 and conditions[0]["data"]["m_ConditionMode"] == 1
        assert not transition["m_HasExitTime"]
        triggers[names[conditions[0]["data"]["m_EventID"]]] = transition
    return {"go": animator.m_GameObject.path_id, "children": sorted(set(paths.values())),
            "default": machine["m_DefaultState"], "states": states, "triggers": triggers}
