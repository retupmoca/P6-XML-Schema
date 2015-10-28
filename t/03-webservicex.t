use v6;

use Test;

plan 11;

use XML::Schema;

# from http://www.webservicex.net/ConvertTemperature.asmx?WSDL
my $temp-schema-raw = q:to/TSEND/;
<s:schema xmlns:tns="http://www.webserviceX.NET/"
          xmlns:s="http://www.w3.org/2001/XMLSchema"
          elementFormDefault="qualified"
          targetNamespace="http://www.webserviceX.NET/">
      <s:element name="ConvertTemp">
        <s:complexType>
          <s:sequence>
            <s:element minOccurs="1" maxOccurs="1" name="Temperature" type="s:double" />
            <s:element minOccurs="1" maxOccurs="1" name="FromUnit" type="tns:TemperatureUnit" />
            <s:element minOccurs="1" maxOccurs="1" name="ToUnit" type="tns:TemperatureUnit" />
          </s:sequence>
        </s:complexType>
      </s:element>
      <s:simpleType name="TemperatureUnit">
        <s:restriction base="s:string">
          <s:enumeration value="degreeCelsius" />
          <s:enumeration value="degreeFahrenheit" />
          <s:enumeration value="degreeRankine" />
          <s:enumeration value="degreeReaumur" />
          <s:enumeration value="kelvin" />
        </s:restriction>
      </s:simpleType>
      <s:element name="ConvertTempResponse">
        <s:complexType>
          <s:sequence>
            <s:element minOccurs="1" maxOccurs="1" name="ConvertTempResult" type="s:double" />
          </s:sequence>
        </s:complexType>
      </s:element>
      <s:element name="double" type="s:double" />
    </s:schema>
TSEND

my $temp-schema = XML::Schema.new(:schema($temp-schema-raw));
ok $temp-schema ~~ XML::Schema, 'Able to create temp schema';

my $xml = $temp-schema.to-xml(ConvertTemp => {Temperature => 32,
                                              FromUnit => 'degreeCelsius',
                                              ToUnit => 'degreeFahrenheit'});
ok $xml ~~ XML::Document, 'Got a valid to-xml';

my $data = $temp-schema.from-xml($xml);
ok $data ~~ Hash, 'Got data back';
ok $data<ConvertTemp>:exists, 'with good top level';
is $data<ConvertTemp><Temperature>, 32, 'and good data';

# from http://www.webservicex.net/Statistics.asmx?WSDL
my $stats-schema-raw = q:to/SSEND/;
<s:schema xmlns:tns="http://www.webserviceX.NET/"
          xmlns:s="http://www.w3.org/2001/XMLSchema"
          elementFormDefault="qualified"
          targetNamespace="http://www.webserviceX.NET/">
      <s:element name="GetStatistics">
        <s:complexType>
          <s:sequence>
            <s:element minOccurs="0" maxOccurs="1" name="X" type="tns:ArrayOfDouble" />
          </s:sequence>
        </s:complexType>
      </s:element>
      <s:complexType name="ArrayOfDouble">
        <s:sequence>
          <s:element minOccurs="0" maxOccurs="unbounded" name="double" type="s:double" />
        </s:sequence>
      </s:complexType>
      <s:element name="GetStatisticsResponse">
        <s:complexType>
          <s:sequence>
            <s:element minOccurs="1" maxOccurs="1" name="Sums" type="s:double" />
            <s:element minOccurs="1" maxOccurs="1" name="Average" type="s:double" />
            <s:element minOccurs="1" maxOccurs="1" name="StandardDeviation" type="s:double" />
            <s:element minOccurs="1" maxOccurs="1" name="skewness" type="s:double" />
            <s:element minOccurs="1" maxOccurs="1" name="Kurtosis" type="s:double" />
          </s:sequence>
        </s:complexType>
      </s:element>
    </s:schema>
SSEND

my $stats-schema = XML::Schema.new(:schema($stats-schema-raw));
ok $stats-schema ~~ XML::Schema, 'Able to create stats schema';

$xml = $stats-schema.to-xml(GetStatistics => { X => { double => [ 1, 2, 3 ] }});
ok $xml ~~ XML::Document, 'Got a valid to-xml';

$data = $stats-schema.from-xml($xml);
ok $data ~~ Hash, 'Got data back';
ok $data<GetStatistics>:exists, 'with good top level';
ok $data<GetStatistics><X><double> ~~ Array, 'array comes back correctly';
is $data<GetStatistics><X><double>[1], 2, 'and good data';
