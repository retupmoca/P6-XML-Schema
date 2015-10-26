use v6;

use Test;

plan 6;

use XML::Schema;

ok 1, 'Module loaded';

# from https://en.wikipedia.org/wiki/XML_Schema_(W3C)#Example
my $schema-raw = q:to/END/;
<?xml version="1.0" encoding="utf-8"?>
<xs:schema elementFormDefault="qualified" xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xs:element name="Address">
    <xs:complexType>
      <xs:sequence>
        <xs:element name="Recipient" type="xs:string" />
        <xs:element name="House" type="xs:string" />
        <xs:element name="Street" type="xs:string" />
        <xs:element name="Town" type="xs:string" />
        <xs:element name="County" type="xs:string" minOccurs="0" />
        <xs:element name="PostCode" type="xs:string" />
        <xs:element name="Country" minOccurs="0">
          <xs:simpleType>
            <xs:restriction base="xs:string">
              <xs:enumeration value="IN" />
              <xs:enumeration value="DE" />
              <xs:enumeration value="ES" />
              <xs:enumeration value="UK" />
              <xs:enumeration value="US" />
            </xs:restriction>
          </xs:simpleType>
        </xs:element>
      </xs:sequence>
    </xs:complexType>
  </xs:element>
</xs:schema>
END

my $schema = XML::Schema.new(:schema($schema-raw));
ok $schema ~~ XML::Schema, 'Able to create object from schema';

my $xml = $schema.to-xml(Address => { Recipient => 'Owner',
                                      House     => '1234',
                                      Street    => 'Main St',
                                      Town      => 'Example',
                                      PostCode  => '12345',
                                      Country   => 'US'});
ok $xml ~~ XML::Document, 'Got a valid XML document from perl data';

my $data = $schema.from-xml($xml);
todo 'NYI', 1;
ok $data ~~ Hash, 'Got some perl data back from XML';
skip 'NYI', 2;
if 0 {
ok $data == 1, 'With one top-level key';
ok $data<Address> == 6, 'and the correct number of sub-elements';
}
