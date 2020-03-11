import six

from gssapi.raw import oids as roids
from gssapi._utils import import_gssapi_extension
from gssapi.raw import misc as rmisc
from gssapi import _utils
from gssapi.raw.named_tuples import InquireSASLNameResult, InquireAttrsResult
from gssapi.raw.names import Name

from typing import cast, Any, Iterator, List, Optional, Set

rfc5587 = import_gssapi_extension('rfc5587')
rfc5801 = import_gssapi_extension('rfc5801')

class Mechanism(roids.OID):
    """
    A GSSAPI Mechanism

    This class represents a mechanism and centralizes functions dealing with
    mechanisms and can be used with any calls.

    It inherits from the low-level GSSAPI :class:`~gssapi.raw.oids.OID` class,
    and thus can be used with both low-level and high-level API calls.
    """
    def __new__(cls, cpy: Optional[roids.OID],
                elements: Optional[bytes] = None) -> Any:
        return super(Mechanism, cls).__new__(cls, cpy, elements)

    @property
    def name_types(self) -> List[roids.OID]:
        """
        Get the set of name types supported by this mechanism.
        """
        return rmisc.inquire_names_for_mech(self)

    @property
    def _saslname(self) -> InquireSASLNameResult:
        if rfc5801 is None:
            raise NotImplementedError("Your GSSAPI implementation does not "
                                      "have support for RFC 5801")

        res = rfc5801.inquire_saslname_for_mech(self)
        return cast(InquireSASLNameResult, res)

    @property
    def _attrs(self) -> InquireAttrsResult:
        if rfc5587 is None:
            raise NotImplementedError("Your GSSAPI implementation does not "
                                      "have support for RFC 5587")

        res = rfc5587.inquire_attrs_for_mech(self)
        return cast(InquireAttrsResult, res)

    def __str__(self) -> str:
        # Python 3 -- we should return unicode
        return self._bytes_desc().decode(_utils._get_encoding())

    def __unicode__(self) -> str:
        return self._bytes_desc().decode(_utils._get_encoding())

    def _bytes_desc(self) -> bytes:
        base = self.dotted_form.encode(_utils._get_encoding())
        if rfc5801 is not None and self._saslname and self._saslname.mech_name:
            return self._saslname.mech_name

        return base

    def __repr__(self) -> str:
        """
        Get a name representing the mechanism; always safe to call
        """
        base = "<Mechanism (%s)>" % self.dotted_form
        if rfc5801 is not None:
            base = "<Mechanism %s (%s)>" % (
                self._saslname.mech_name.decode('UTF-8'),
                self.dotted_form
            )

        return base

    @property
    def sasl_name(self) -> str:
        """
        Get the SASL name for the mechanism

        :requires-ext:`rfc5801`
        """
        return self._saslname.sasl_mech_name.decode("UTF-8")

    @property
    def description(self) -> str:
        """
        Get the description of the mechanism

        :requires-ext:`rfc5801`
        """
        return self._saslname.mech_description.decode('UTF-8')

    @property
    def known_attrs(self) -> Set[roids.OID]:
        """
        Get the known attributes of the mechanism; returns a set of OIDs
        ([OID])

        :requires-ext:`rfc5587`
        """
        return self._attrs.known_mech_attrs

    @property
    def attrs(self) -> Set[roids.OID]:
        """
        Get the attributes of the mechanism; returns a set of OIDs ([OID])

        :requires-ext:`rfc5587`
        """
        return self._attrs.mech_attrs

    @classmethod
    def all_mechs(cls) -> Iterator[Mechanism]:
        """
        Get a generator of all mechanisms supported by GSSAPI
        """
        return (cls(mech) for mech in rmisc.indicate_mechs())

    @classmethod
    def from_name(cls, name: Name) -> Iterator[Mechanism]:
        """
        Get a generator of mechanisms that may be able to process the name

        Args:
            name (Name): a name to inquire about

        Returns:
            [Mechanism]: a set of mechanisms which support this name

        Raises:
            GSSError
        """
        return (cls(mech) for mech in rmisc.inquire_mechs_for_name(name))

    @classmethod
    def from_sasl_name(cls, name: Name) -> Mechanism:
        """
        Create a Mechanism from its SASL name

        Args:
            name (str): SASL name of the desired mechanism

        Returns:
            Mechanism: the desired mechanism

        Raises:
            GSSError

        :requires-ext:`rfc5801`
        """
        if rfc5801 is None:
            raise NotImplementedError("Your GSSAPI implementation does not "
                                      "have support for RFC 5801")
        if isinstance(name, six.text_type):
            name = name.encode(_utils._get_encoding())

        m = rfc5801.inquire_mech_for_saslname(name)

        return cls(m)

    Attrs = Optional[List[roids.OID]]
    @classmethod
    def from_attrs(cls, desired_attrs: Attrs = None,
                   except_attrs: Attrs = None,
                   critical_attrs: Attrs = None) -> Iterator[Mechanism]:
        """
        Get a generator of mechanisms supporting the specified attributes. See
        RFC 5587's :func:`indicate_mechs_by_attrs` for more information.

        Args:
            desired_attrs ([OID]): Desired attributes
            except_attrs ([OID]): Except attributes
            critical_attrs ([OID]): Critical attributes

        Returns:
            [Mechanism]: A set of mechanisms having the desired features.

        Raises:
            GSSError

        :requires-ext:`rfc5587`
        """
        if isinstance(desired_attrs, roids.OID):
            desired_attrs = set([desired_attrs])
        if isinstance(except_attrs, roids.OID):
            except_attrs = set([except_attrs])
        if isinstance(critical_attrs, roids.OID):
            critical_attrs = set([critical_attrs])

        if rfc5587 is None:
            raise NotImplementedError("Your GSSAPI implementation does not "
                                      "have support for RFC 5587")

        mechs = rfc5587.indicate_mechs_by_attrs(desired_attrs,
                                                except_attrs,
                                                critical_attrs)
        return (cls(mech) for mech in mechs)
