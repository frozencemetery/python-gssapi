from gssapi.raw.cython_types cimport *
from gssapi.raw.oids cimport OID

from gssapi.raw.types import MechType, NameType


cdef gss_OID_set c_get_mech_oid_set(object mechs):
    """Convert a list of MechType values into an OID set."""

    cdef gss_OID_set res_set
    cdef OM_uint32 min_stat
    gss_create_empty_oid_set(&min_stat, &res_set)

    cdef gss_OID oid
    for mech in mechs:
        oid = &(<OID>mech).raw_oid
        gss_add_oid_set_member(&min_stat, oid, &res_set)

    return res_set


cdef object c_create_mech_list(gss_OID_set mech_set, bint free=True):
    """Convert a set of GSS mechanism OIDs to a list of MechType values."""

    l = []
    cdef i
    for i in range(mech_set.count):
        mech_type = OID()
        mech_type._copy_from(mech_set.elements[i])
        l.append(mech_type)

    cdef OM_uint32 tmp_min_stat
    if free:
        gss_release_oid_set(&tmp_min_stat, &mech_set)

    return l
