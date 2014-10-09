GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from gssapi.raw.cython_types cimport *
from gssapi.raw.cython_converters cimport c_py_ttl_to_c, c_c_ttl_to_py
from gssapi.raw.creds cimport Creds
from gssapi.raw.names cimport Name
from gssapi.raw.oids cimport OID

from gssapi.raw.types import MechType, RequirementFlag, IntEnumFlagSet
from gssapi.raw.misc import GSSError
from gssapi.raw.named_tuples import AcceptSecContextResult
from gssapi.raw.named_tuples import InitSecContextResult
from gssapi.raw.named_tuples import InquireContextResult


cdef extern from "gssapi.h":
    OM_uint32 gss_init_sec_context(OM_uint32 *min_stat,
                                   const gss_cred_id_t initiator_creds,
                                   gss_ctx_id_t *context,
                                   const gss_name_t target_name,
                                   const gss_OID mech_type,
                                   OM_uint32 flags,
                                   OM_uint32 ttl,
                                   const gss_channel_bindings_t chan_bdgs,
                                   const gss_buffer_t input_token,
                                   gss_OID *actual_mech_type,
                                   gss_buffer_t output_token,
                                   OM_uint32 *actual_flags,
                                   OM_uint32 *actual_ttl) nogil

    OM_uint32 gss_accept_sec_context(OM_uint32 *min_stat,
                                     gss_ctx_id_t *context,
                                     const gss_cred_id_t acceptor_creds,
                                     const gss_buffer_t input_token,
                                     const gss_channel_bindings_t chan_bdgs,
                                     const gss_name_t *initiator_name,
                                     gss_OID *mech_type,
                                     gss_buffer_t output_token,
                                     OM_uint32 *flags,
                                     OM_uint32 *ttl,
                                     gss_cred_id_t *delegated_creds) nogil

    OM_uint32 gss_delete_sec_context(OM_uint32 *min_stat,
                                     gss_ctx_id_t *context,
                                     gss_buffer_t output_token) nogil

    OM_uint32 gss_process_context_token(OM_uint32 *min_stat,
                                        const gss_ctx_id_t context,
                                        const gss_buffer_t token) nogil

    OM_uint32 gss_context_time(OM_uint32 *min_stat,
                               const gss_ctx_id_t context_handle,
                               OM_uint32 *ttl) nogil

    OM_uint32 gss_inquire_context(OM_uint32 *min_stat,
                                  const gss_ctx_id_t context,
                                  gss_name_t *initiator_name,
                                  gss_name_t *target_name,
                                  OM_uint32 *ttl,
                                  gss_OID *mech_type,
                                  OM_uint32 *ctx_flags,
                                  int *locally_initiated,
                                  int *is_open) nogil

    OM_uint32 gss_export_sec_context(OM_uint32 *min_stat,
                                     gss_ctx_id_t *context,
                                     gss_buffer_t interprocess_token) nogil

    OM_uint32 gss_import_sec_context(OM_uint32 *min_stat,
                                     const gss_buffer_t interprocess_token,
                                     gss_ctx_id_t *context) nogil


cdef class SecurityContext:
    """
    A GSSAPI Context
    """
    # defined in pxd
    # cdef gss_ctx_id_t raw_ctx

    def __cinit__(self, SecurityContext cpy=None):
        if cpy is not None:
            self.raw_ctx = cpy.raw_ctx
            cpy._free_on_dealloc = False  # prevent deletion of the context
        else:
            self.raw_ctx = GSS_C_NO_CONTEXT

        self._free_on_dealloc = True

    property _started:
        """Whether the underlying context is NULL."""

        def __get__(self):
            return self.raw_ctx is not NULL

    def __dealloc__(self):
        # basically just deleteSecContext, but we are not
        # allowed to call methods here
        cdef OM_uint32 maj_stat, min_stat
        if self.raw_ctx is not NULL and self._free_on_dealloc:
            # local deletion only
            maj_stat = gss_delete_sec_context(&min_stat, &self.raw_ctx,
                                              GSS_C_NO_BUFFER)
            if maj_stat != GSS_S_COMPLETE:
                raise GSSError(maj_stat, min_stat)

            self.raw_ctx = NULL


# TODO(sross): add support for channel bindings
# TODO(sross): figure out whether GSS_C_NO_NAME can be passed in here
def initSecContext(Name target_name not None, Creds cred=None,
                   SecurityContext context=None,
                   OID mech_type=None,
                   flags=None, ttl=None, channel_bindings=None,
                   input_token=None):
    """
    initSecContext(target_name, cred=None, context=None, mech_type=None,
                   flags=None, tll=None, channel_bindings=None,
                   input_token=None) -> (SecurityContext, MechType,
                                         [RequirementFlag], bytes, int, bool)
    Initiate a GSSAPI Security Context.

    This method initiates a GSSAPI security context, targeting the given
    target name.  To create a basic context, just provide the target name.
    Further calls used to update the context should pass in the output context
    of the last call, as well as the input token received from the acceptor.

    Warning:
        This changes the input context!

    Args:
        target_name (Name): the target for the security context
        cred (Creds): the credentials to use to initiate the context,
            or None to use the default credentials
        context (SecurityContext): the security context to update, or
            None to create a new context
        mech_type (MechType): the mechanism type for this security context,
            or None for the default mechanism type
        flags ([RequirementFlag]): the flags to request for the security
            context, or None to use the default set: mutual_authentication and
            out_of_sequence_detection
        ttl (int): the request lifetime of the security context (a value of
            0 or None means indefinite)
        channel_bindings (ChannelBindings): NCI
        input_token (bytes): the token to use to update the security context,
            or None if you are creating a new context

    Returns:
        (SecurityContext, MechType, [RequirementFlag], bytes, int, bool): the
            output security context, the actual mech type, the actual flags
            used, the output token to send to the acceptor, the actual
            lifetime of the context (or None if not supported or indefinite),
            and whether or not more calls are needed to finish the initiation.

    Raises:
        GSSError
    """

    cdef gss_OID mech_oid
    if mech_type is not None:
        mech_oid = &mech_type.raw_oid
    else:
        mech_oid = GSS_C_NO_OID

    # TODO(directxman12): should we default to this?
    cdef OM_uint32 req_flags = IntEnumFlagSet(RequirementFlag, flags or [
        RequirementFlag.mutual_authentication,
        RequirementFlag.out_of_sequence_detection])

    cdef gss_channel_bindings_t bdng = GSS_C_NO_CHANNEL_BINDINGS
    # TODO(sross): just import GSS_C_EMPTY_BUFFER == gss_buffer_desc(0, NULL)
    cdef gss_buffer_desc input_token_buffer = gss_buffer_desc(0, NULL)

    cdef OM_uint32 input_ttl = c_py_ttl_to_c(ttl)

    cdef SecurityContext output_context = context
    if output_context is None:
        output_context = SecurityContext()

    cdef gss_cred_id_t act_cred
    if cred is not None:
        act_cred = cred.raw_creds
    else:
        act_cred = GSS_C_NO_CREDENTIAL

    if input_token is not None:
        input_token_buffer.value = input_token
        input_token_buffer.length = len(input_token)

    cdef gss_OID actual_mech_type
    # TODO(sross): just import GSS_C_EMPTY_BUFFER == gss_buffer_desc(0, NULL)
    cdef gss_buffer_desc output_token_buffer = gss_buffer_desc(0, NULL)
    cdef OM_uint32 ret_flags
    cdef OM_uint32 output_ttl

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_init_sec_context(&min_stat, act_cred,
                                        &output_context.raw_ctx,
                                        target_name.raw_name,
                                        mech_oid, req_flags, input_ttl,
                                        bdng, &input_token_buffer,
                                        &actual_mech_type,
                                        &output_token_buffer,
                                        &ret_flags, &output_ttl)

    cdef OID output_mech_type = OID()
    if maj_stat == GSS_S_COMPLETE or maj_stat == GSS_S_CONTINUE_NEEDED:
        output_mech_type.raw_oid = actual_mech_type[0]
        output_token = output_token_buffer.value[:output_token_buffer.length]
        res = InitSecContextResult(output_context, output_mech_type,
                                   IntEnumFlagSet(RequirementFlag, ret_flags),
                                   output_token,
                                   c_c_ttl_to_py(output_ttl),
                                   maj_stat == GSS_S_CONTINUE_NEEDED)
        gss_release_buffer(&min_stat, &output_token_buffer)
        return res
    else:
        raise GSSError(maj_stat, min_stat)


def acceptSecContext(input_token not None, Creds acceptor_cred=None,
                     SecurityContext context=None, channel_bindings=None):
    """
    acceptSecContext(input_token, acceptor_cred=None, context=None,
                     channel_bindings=None) -> (SecurityContext, Name,
                                                MechType, bytes,
                                                [RequirementFlag], int, Creds,
                                                bool)
    Accept a GSSAPI security context.

    This method accepts a GSSAPI security context using a token sent by the
    initiator, using the given credentials.  It can either be used to accept a
    security context and create a new security context object, or to update an
    existing security context object.

    Warning:
        This changes the input context!

    Args:
        input_token (bytes): the token sent by the context initiator
        acceptor_cred (Creds): the credentials to be used to accept the context
            (or None to use the default credentials)
        context (SecurityContext): the security context to update
            (or None to create a new security context object)
        channel_bindings: NCI

    Returns:
        (SecurityContext, Name, MechType, bytes, [RequirementFlag], int,
         Creds, bool): the resulting security context, the initiator name,
            the mechanism being used, the output token, the flags in use, the
            lifetime of the context (or None for indefinite or not supported),
            the delegated credentials (valid only if the delegate_to_peer flag
            is set), and whether or not further token exchanges are needed to
            finalize the security context.

    Raises:
        GSSError
    """

    cdef gss_channel_bindings_t bdng = GSS_C_NO_CHANNEL_BINDINGS
    cdef gss_buffer_desc input_token_buffer = gss_buffer_desc(len(input_token),
                                                              input_token)

    cdef SecurityContext output_context = context
    if output_context is None:
        output_context = SecurityContext()

    cdef gss_cred_id_t act_acceptor_cred
    if acceptor_cred is None:
        act_acceptor_cred = acceptor_cred.raw_creds
    else:
        act_acceptor_cred = GSS_C_NO_CREDENTIAL

    cdef gss_name_t initiator_name
    cdef gss_OID mech_type
    # GSS_C_EMPTY_BUFFER
    cdef gss_buffer_desc output_token_buffer = gss_buffer_desc(0, NULL)
    cdef OM_uint32 ret_flags
    cdef OM_uint32 output_ttl
    cdef gss_cred_id_t delegated_cred

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_accept_sec_context(&min_stat, &output_context.raw_ctx,
                                          act_acceptor_cred,
                                          &input_token_buffer, bdng,
                                          &initiator_name,
                                          &mech_type, &output_token_buffer,
                                          &ret_flags, &output_ttl,
                                          &delegated_cred)

    cdef Name on = Name()
    cdef Creds oc = Creds()
    cdef OID py_mech_type
    if maj_stat == GSS_S_COMPLETE or maj_stat == GSS_S_CONTINUE_NEEDED:
        if output_ttl == GSS_C_INDEFINITE:
            output_ttl_py = None
        else:
            output_ttl_py = output_ttl

        output_token = output_token_buffer.value[:output_token_buffer.length]
        on.raw_name = initiator_name
        oc.raw_creds = delegated_cred
        if mech_type is not NULL:
            py_mech_type = OID()
            py_mech_type.raw_oid = mech_type[0]
        else:
            py_mech_type = None

        res = AcceptSecContextResult(output_context, on, py_mech_type,
                                     output_token,
                                     IntEnumFlagSet(RequirementFlag,
                                                    ret_flags),
                                     output_ttl_py, oc,
                                     maj_stat == GSS_S_CONTINUE_NEEDED)
        gss_release_buffer(&min_stat, &output_token_buffer)
        return res
    else:
        raise GSSError(maj_stat, min_stat)


def inquireContext(SecurityContext context not None, initiator_name=True,
                   target_name=True, lifetime=True, mech_type=True, flags=True,
                   locally_init=True, complete=True):
    """
    inquireContext(context) -> (Name, Name, int, MechType, [RequirementFlag],
                                bool, bool)
    Get information about a security context.

    This method obtains information about a security context, including
    the initiator and target names, as well as the TTL, mech type,
    flags, and its current state (open vs closed).

    Note: the target name may be None if it would have been GSS_C_NO_NAME

    Args:
        context (SecurityContext): the context in question

    Returns:
        (Name, Name, int, MechType, [RequirementFlag], bool, bool): the
            initiator name, the target name, the TTL (can be None for
            indefinite or not supported), the mech type, the
            flags, whether or not the context was locally initiated,
            and whether or not the context is currently fully established

    Raises:
        GSSError
    """

    cdef gss_name_t output_init_name
    cdef gss_name_t *init_name_ptr = NULL
    if initiator_name:
        init_name_ptr = &output_init_name

    cdef gss_name_t output_target_name
    cdef gss_name_t *target_name_ptr = NULL
    if target_name:
        target_name_ptr = &output_target_name

    cdef OM_uint32 ttl
    cdef OM_uint32 *ttl_ptr = NULL
    if lifetime:
        ttl_ptr = &ttl

    cdef gss_OID output_mech_type
    cdef gss_OID *mech_type_ptr = NULL
    if mech_type:
        mech_type_ptr = &output_mech_type

    cdef OM_uint32 output_flags
    cdef OM_uint32 *flags_ptr = NULL
    if flags:
        flags_ptr = &output_flags

    cdef int output_locally_init
    cdef int *locally_init_ptr = NULL
    if locally_init:
        locally_init_ptr = &output_locally_init

    cdef int is_complete
    cdef int *is_complete_ptr = NULL
    if complete:
        is_complete_ptr = &is_complete

    cdef OM_uint32 maj_stat, min_stat

    maj_stat = gss_inquire_context(&min_stat, context.raw_ctx, init_name_ptr,
                                   target_name_ptr, ttl_ptr, mech_type_ptr,
                                   flags_ptr, locally_init_ptr,
                                   is_complete_ptr)

    cdef Name sn
    cdef OID py_mech_type
    cdef Name tn
    if maj_stat == GSS_S_COMPLETE:
        if initiator_name:
            sn = Name()
            sn.raw_name = output_init_name
        else:
            sn = None

        if target_name and output_target_name != GSS_C_NO_NAME:
            tn = Name()
            tn.raw_name = output_target_name
        else:
            tn = None

        if mech_type:
            py_mech_type = OID()
            py_mech_type.raw_oid = output_mech_type[0]
        else:
            py_mech_type = None

        if lifetime and ttl != GSS_C_INDEFINITE:
            py_ttl = ttl
        else:
            py_ttl = None

        if flags:
            py_flags = IntEnumFlagSet(RequirementFlag, output_flags)
        else:
            py_flags = None

        if locally_init:
            py_locally_init = <bint>output_locally_init
        else:
            py_locally_init = None

        if complete:
            py_complete = <bint>is_complete
        else:
            py_complete = None

        return InquireContextResult(sn, tn, py_ttl, py_mech_type, py_flags,
                                    py_locally_init, py_complete)
    else:
        raise GSSError(maj_stat, min_stat)


def contextTime(SecurityContext context not None):
    """
    contextTime(context) -> int
    Get the amount of time for which the given context will remain valid.

    This method determines the amount of time for which the given
    security context will remain valid.  An expired context will
    give a result of 0.

    Args:
        context (SecurityContext): the security context in question

    Returns:
        int: the number of seconds for which the context will be valid

    Raises:
        GSSError
    """

    cdef OM_uint32 ttl

    cdef OM_uint32 maj_stat, min_stat

    maj_stat = gss_context_time(&min_stat, context.raw_ctx, &ttl)

    if maj_stat == GSS_S_COMPLETE:
        return ttl
    else:
        raise GSSError(maj_stat, min_stat)


def processContextToken(SecurityContext context not None, token):
    """
    processContextToken(context, token)
    Process a token asynchronously

    This method provides a way to process a token, even if the
    given security context is not expecting one.  For example,
    if the initiator has the initSecContext return that the context
    is complete, but the acceptor is unable to accept the context,
    and wishes to send a token to the initiator, letting the
    initiator know of the error.

    Args:
        context (SecurityContext): the security context against which
            to process the token
        token (bytes): the token to process

    Raises:
        GSSError
    """

    cdef gss_buffer_desc token_buffer = gss_buffer_desc(len(token), token)

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_process_context_token(&min_stat, context.raw_ctx,
                                             &token_buffer)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)


def importSecContext(token not None):
    """
    importSecContext(token) -> SecurityContext
    Import a context from another process

    This method imports a security context established in another process
    by reading the specified token which was output by exportSecContext.
    """

    cdef gss_buffer_desc token_buffer = gss_buffer_desc(len(token), token)

    cdef gss_ctx_id_t ctx

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_import_sec_context(&min_stat, &token_buffer, &ctx)

    if maj_stat == GSS_S_COMPLETE:
        res = SecurityContext()
        res.raw_ctx = ctx
        return res
    else:
        raise GSSError(maj_stat, min_stat)


def exportSecContext(SecurityContext context not None):
    """
    exportSecContext(context) -> bytes
    Export a context for use in another process

    This method exports a security context, deactivating in the current process
    and creating a token which can then be imported into another process
    with importSecContext.

    Warning: this modifies the input context

    Args:
        context (SecurityContext): the context to send to another process

    Returns:
        bytes: the output token to be imported

    Raises:
        GSSError
    """

    cdef gss_buffer_desc output_token = gss_buffer_desc(0, NULL)

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_export_sec_context(&min_stat, &context.raw_ctx,
                                          &output_token)

    if maj_stat == GSS_S_COMPLETE:
        res_token = output_token.value[:output_token.length]
        gss_release_buffer(&min_stat, &output_token)
        return res_token
    else:
        raise GSSError(maj_stat, min_stat)


def deleteSecContext(SecurityContext context not None, local_only=True):
    """
    deleteSecContext(context) -> bytes or None
    Delete a GSSAPI Security Context.

    This method deletes a GSSAPI security context,
    returning an output token to send to the other
    holder of the security context to notify them
    of the deletion.

    Args:
        context (SecurityContext): the security context in question
        local_only (bool): should we request local deletion (True), or also
            remote deletion (False), in which case a token is also returned

    Returns:
        bytes or None: the output token (if remote deletion is requested)

    Raises:
        GSSError
    """

    cdef OM_uint32 maj_stat, min_stat
    # GSS_C_EMPTY_BUFFER
    cdef gss_buffer_desc output_token = gss_buffer_desc(0, NULL)
    if not local_only:
        maj_stat = gss_delete_sec_context(&min_stat, &context.raw_ctx,
                                          &output_token)
    else:
        maj_stat = gss_delete_sec_context(&min_stat, &context.raw_ctx,
                                          GSS_C_NO_BUFFER)

    if maj_stat == GSS_S_COMPLETE:
        res = output_token.value[:output_token.length]
        context.raw_ctx = NULL
        return res
    else:
        raise GSSError(maj_stat, min_stat)