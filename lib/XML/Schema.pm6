use XML;

unit class XML::Schema;

has $.schema;

multi method new(XML::Document :$schema!) {
    self.bless(:$schema);
}

multi method new(Str :$schema!) {
    self.new(:schema(from-xml($schema)));
}

multi method new(IO :$schema!) {
    self.new(:schema(from-xml-stream($schema)));
}

multi method to-xml(%data) {
    die "Please pass exactly one root element" if %data != 1;
    fail "NYI";
}

multi method to-xml(*%data) {
    self.to-xml(%data);
}

multi method from-xml(XML::Document $xml) {
    fail "NYI";
}

multi method from-xml(Str $xml) {
    self.from-xml(from-xml($xml));
}

multi method from-xml(IO $xml) {
    self.from-xml(from-xml-stream($xml));
}
