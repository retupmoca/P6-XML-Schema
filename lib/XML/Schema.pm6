use XML;

unit class XML::Schema;

has $.schema;

multi method new(XML::Document :$schema!) {
    self.bless(:$schema);
}

multi method new(Str :$schema!) {
    self.new(:schema(from-xml($schema)));
}

multi method new(Str :$schema-file!) {
    self.new(:schema(from-xml-file($schema-file)));
}

multi method new(IO :$schema!) {
    self.new(:schema(from-xml-stream($schema)));
}
