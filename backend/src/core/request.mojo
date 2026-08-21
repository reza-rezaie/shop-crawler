# PythonObject request/query-param dict helpers shared by every module's
# handler functions (api.mojo used to keep these private to itself, back
# when it also contained every handler's own body -- now that handler
# logic lives in each owning module, these need to be importable across
# module boundaries, so they live here rather than duplicated per module).
# See openspec/changes/chg-0001-2026-08-21-modular-monolith-vertical-slice/
# design.md, Decision 8.

from std.python import Python, PythonObject


def get_str(d: PythonObject, key: String, default: String = String("")) raises -> String:
    var val = d.get(key)
    if val is None:
        return default
    return String(val)


def get_int(d: PythonObject, key: String, default: Int) raises -> Int:
    var val = d.get(key)
    if val is None:
        return default
    try:
        return Int(String(val))
    except e:
        return default


def get_bool(d: PythonObject, key: String, default: Bool) raises -> Bool:
    var val = d.get(key)
    if val is None:
        return default
    return Bool(val)


def get_obj(d: PythonObject, key: String) raises -> PythonObject:
    """Raw value for `key`, or Python None if absent -- used for the
    internal `_progress` dict server.py smuggles into the request so a
    long-running crawl/discovery run can report live progress into a
    PythonObject the HTTP layer already holds a reference to (see
    crawler.crawl's own docstring for why a dict rather than a callback)."""
    return d.get(key)


def get_optional_float(d: PythonObject, key: String) raises -> Optional[Float64]:
    var val = d.get(key)
    if val is None:
        return None
    var text = String(val).strip()
    if text.byte_length() == 0:
        return None
    try:
        return Optional[Float64](Float64(text))
    except e:
        return None
