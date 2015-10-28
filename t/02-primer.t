use v6;

use Test;

plan 6;

use XML::Schema;

# tests in the file are based on http://www.w3.org/TR/xmlschema-0/

my $po-raw = q:to/POR/;
<?xml version="1.0"?>
<purchaseOrder orderDate="1999-10-20">
   <shipTo country="US">
      <name>Alice Smith</name>
      <street>123 Maple Street</street>
      <city>Mill Valley</city>
      <state>CA</state>
      <zip>90952</zip>
   </shipTo>
   <billTo country="US">
      <name>Robert Smith</name>
      <street>8 Oak Avenue</street>
      <city>Old Town</city>
      <state>PA</state>
      <zip>95819</zip>
   </billTo>
   <comment>Hurry, my lawn is going wild!</comment>
   <items>
      <item partNum="872-AA">
         <productName>Lawnmower</productName>
         <quantity>1</quantity>
         <USPrice>148.95</USPrice>
         <comment>Confirm this is electric</comment>
      </item>
      <item partNum="926-AA">
         <productName>Baby Monitor</productName>
         <quantity>1</quantity>
         <USPrice>39.98</USPrice>
         <shipDate>1999-05-21</shipDate>
      </item>
   </items>
</purchaseOrder>
POR

my $po-schema-raw = q:to/POSR/;
<xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">

  <xsd:annotation>
    <xsd:documentation xml:lang="en">
     Purchase order schema for Example.com.
     Copyright 2000 Example.com. All rights reserved.
    </xsd:documentation>
  </xsd:annotation>

  <xsd:element name="purchaseOrder" type="PurchaseOrderType"/>

  <xsd:element name="comment" type="xsd:string"/>

  <xsd:complexType name="PurchaseOrderType">
    <xsd:sequence>
      <xsd:element name="shipTo" type="USAddress"/>
      <xsd:element name="billTo" type="USAddress"/>
      <xsd:element ref="comment" minOccurs="0"/>
      <xsd:element name="items"  type="Items"/>
    </xsd:sequence>
    <xsd:attribute name="orderDate" type="xsd:date"/>
  </xsd:complexType>

  <xsd:complexType name="USAddress">
    <xsd:sequence>
      <xsd:element name="name"   type="xsd:string"/>
      <xsd:element name="street" type="xsd:string"/>
      <xsd:element name="city"   type="xsd:string"/>
      <xsd:element name="state"  type="xsd:string"/>
      <xsd:element name="zip"    type="xsd:decimal"/>
    </xsd:sequence>
    <xsd:attribute name="country" type="xsd:NMTOKEN"
                   fixed="US"/>
  </xsd:complexType>

  <xsd:complexType name="Items">
    <xsd:sequence>
      <xsd:element name="item" minOccurs="0" maxOccurs="unbounded">
        <xsd:complexType>
          <xsd:sequence>
            <xsd:element name="productName" type="xsd:string"/>
            <xsd:element name="quantity">
              <xsd:simpleType>
                <xsd:restriction base="xsd:positiveInteger">
                  <xsd:maxExclusive value="100"/>
                </xsd:restriction>
              </xsd:simpleType>
            </xsd:element>
            <xsd:element name="USPrice"  type="xsd:decimal"/>
            <xsd:element ref="comment"   minOccurs="0"/>
            <xsd:element name="shipDate" type="xsd:date" minOccurs="0"/>
          </xsd:sequence>
          <xsd:attribute name="partNum" type="SKU" use="required"/>
        </xsd:complexType>
      </xsd:element>
    </xsd:sequence>
  </xsd:complexType>

  <!-- Stock Keeping Unit, a code for identifying products -->
  <xsd:simpleType name="SKU">
    <xsd:restriction base="xsd:string">
      <xsd:pattern value="\d{3}-[A-Z]{2}"/>
    </xsd:restriction>
  </xsd:simpleType>

</xsd:schema>
POSR

my $po-schema = XML::Schema.new(:schema($po-schema-raw));
ok $po-schema ~~ XML::Schema, 'Able to create object from basic schema';

my $data = $po-schema.from-xml($po-raw);
ok $data ~~ Hash, 'Able to from-xml example data';

my $po1-raw = q:to/PO1R/;
<?xml version="1.0"?>
<apo:purchaseOrder xmlns:apo="http://www.example.com/PO1"
                   orderDate="1999-10-20">
  <shipTo country="US">
    <name>Alice Smith</name>
    <street>123 Maple Street</street>
    <city>Mill Valley</city>
    <state>CA</state>
    <zip>90952</zip>
  </shipTo>
  <billTo country="US">
    <name>Robert Smith</name>
    <street>8 Oak Avenue</street>
    <city>Old Town</city>
    <state>PA</state>
    <zip>95819</zip>
  </billTo>
  <apo:comment>Hurry, my lawn is going wild!</apo:comment>
   <items>
      <item partNum="872-AA">
         <productName>Lawnmower</productName>
         <quantity>1</quantity>
         <USPrice>148.95</USPrice>
         <apo:comment>Confirm this is electric</apo:comment>
      </item>
      <item partNum="926-AA">
         <productName>Baby Monitor</productName>
         <quantity>1</quantity>
         <USPrice>39.98</USPrice>
         <shipDate>1999-05-21</shipDate>
      </item>
   </items>
</apo:purchaseOrder>
PO1R

my $po1-schema-raw = q:to/PO1SR/;
<schema xmlns="http://www.w3.org/2001/XMLSchema"
        xmlns:po="http://www.example.com/PO1"
        targetNamespace="http://www.example.com/PO1"
        elementFormDefault="unqualified"
        attributeFormDefault="unqualified">

  <element name="purchaseOrder" type="po:PurchaseOrderType"/>
  <element name="comment"       type="string"/>

  <complexType name="PurchaseOrderType">
    <sequence>
      <element name="shipTo"    type="po:USAddress"/>
      <element name="billTo"    type="po:USAddress"/>
      <element ref="po:comment" minOccurs="0"/>
      <element name="items"  type="po:Items"/>
    </sequence>
    <attribute name="orderDate" type="date"/>
  </complexType>

  <complexType name="USAddress">
    <sequence>
      <element name="name"   type="string"/>
      <element name="street" type="string"/>
      <element name="city"   type="string"/>
      <element name="state"  type="string"/>
      <element name="zip"    type="decimal"/>
    </sequence>
    <attribute name="country" type="NMTOKEN"
                   fixed="US"/>
  </complexType>

  <complexType name="Items">
    <sequence>
      <element name="item" minOccurs="0" maxOccurs="unbounded">
        <complexType>
          <sequence>
            <element name="productName" type="string"/>
            <element name="quantity">
              <simpleType>
                <restriction base="positiveInteger">
                  <maxExclusive value="100"/>
                </restriction>
              </simpleType>
            </element>
            <element name="USPrice"  type="decimal"/>
            <element ref="po:comment"   minOccurs="0"/>
            <element name="shipDate" type="date" minOccurs="0"/>
          </sequence>
          <attribute name="partNum" type="po:SKU" use="required"/>
        </complexType>
      </element>
    </sequence>
  </complexType>

  <!-- Stock Keeping Unit, a code for identifying products -->
  <simpleType name="SKU">
    <restriction base="string">
      <pattern value="\d{3}-[A-Z]{2}"/>
    </restriction>
  </simpleType>
</schema>
PO1SR

my $po1-schema = XML::Schema.new(:schema($po1-schema-raw));
ok $po1-schema ~~ XML::Schema, 'Able to create object from targetNamespace schema';

$data = $po1-schema.from-xml($po1-raw);
ok $data ~~ Hash, 'Able to from-xml example data';

my $po1q-raw = q:to/PO1QR/;
<?xml version="1.0"?>
<apo:purchaseOrder xmlns:apo="http://www.example.com/PO1"
                   apo:orderDate="1999-10-20">
  <apo:shipTo country="US">
    <apo:name>Alice Smith</apo:name>
    <apo:street>123 Maple Street</apo:street>
    <apo:city>Mill Valley</apo:city>
    <apo:state>CA</apo:state>
    <apo:zip>90952</apo:zip>
  </apo:shipTo>
  <apo:billTo country="US">
    <apo:name>Robert Smith</apo:name>
    <apo:street>8 Oak Avenue</apo:street>
    <apo:city>Old Town</apo:city>
    <apo:state>PA</apo:state>
    <apo:zip>95819</apo:zip>
  </apo:billTo>
  <apo:comment>Hurry, my lawn is going wild!</apo:comment>
   <apo:items>
      <apo:item partNum="872-AA">
         <apo:productName>Lawnmower</apo:productName>
         <apo:quantity>1</apo:quantity>
         <apo:USPrice>148.95</apo:USPrice>
         <apo:comment>Confirm this is electric</apo:comment>
      </apo:item>
      <apo:item partNum="926-AA">
         <apo:productName>Baby Monitor</apo:productName>
         <apo:quantity>1</apo:quantity>
         <apo:USPrice>39.98</apo:USPrice>
         <apo:shipDate>1999-05-21</apo:shipDate>
      </apo:item>
   </apo:items>
</apo:purchaseOrder>
PO1QR

my $po1q-schema-raw = q:to/PO1QSR/;
<schema xmlns="http://www.w3.org/2001/XMLSchema"
        xmlns:po="http://www.example.com/PO1"
        targetNamespace="http://www.example.com/PO1"
        elementFormDefault="qualified"
        attributeFormDefault="unqualified">

  <element name="purchaseOrder" type="po:PurchaseOrderType"/>
  <element name="comment"       type="string"/>

  <complexType name="PurchaseOrderType">
    <sequence>
      <element name="shipTo"    type="po:USAddress"/>
      <element name="billTo"    type="po:USAddress"/>
      <element ref="po:comment" minOccurs="0"/>
      <element name="items"  type="po:Items"/>
    </sequence>
    <attribute name="orderDate" type="date" form="qualified" />
  </complexType>

  <complexType name="USAddress">
    <sequence>
      <element name="name"   type="string"/>
      <element name="street" type="string"/>
      <element name="city"   type="string"/>
      <element name="state"  type="string"/>
      <element name="zip"    type="decimal"/>
    </sequence>
    <attribute name="country" type="NMTOKEN"
                   fixed="US"/>
  </complexType>

  <complexType name="Items">
    <sequence>
      <element name="item" minOccurs="0" maxOccurs="unbounded">
        <complexType>
          <sequence>
            <element name="productName" type="string"/>
            <element name="quantity">
              <simpleType>
                <restriction base="positiveInteger">
                  <maxExclusive value="100"/>
                </restriction>
              </simpleType>
            </element>
            <element name="USPrice"  type="decimal"/>
            <element ref="po:comment"   minOccurs="0"/>
            <element name="shipDate" type="date" minOccurs="0"/>
          </sequence>
          <attribute name="partNum" type="po:SKU" use="required"/>
        </complexType>
      </element>
    </sequence>
  </complexType>

  <!-- Stock Keeping Unit, a code for identifying products -->
  <simpleType name="SKU">
    <restriction base="string">
      <pattern value="\d{3}-[A-Z]{2}"/>
    </restriction>
  </simpleType>
</schema>
PO1QSR

my $po1q-schema = XML::Schema.new(:schema($po1q-schema-raw));
ok $po1q-schema ~~ XML::Schema, 'Able to create object from targetNamespace qualified schema';

$data = $po1q-schema.from-xml($po1q-raw);
ok $data ~~ Hash, 'Able to from-xml example data';
