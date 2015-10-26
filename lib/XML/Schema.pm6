use XML;

unit class XML::Schema;

has $.schema;

has %!elements;
has %!types;

multi method new(XML::Document :$schema!) {
    self.bless(:$schema);
}

multi method new(Str :$schema!) {
    self.new(:schema(from-xml($schema)));
}

sub build-type($x-e) {
    if $x-e.name eq 'xs:complexType' {
        for $x-e.elements {
            if $_.name eq 'xs:sequence' {
                my @schema-elements;
                for $_.elements {
                   @schema-elements.push((name => $_<name>,
                                          element => build-element($_)).hash);
                }
                return { complex => True, sequence => @schema-elements };
            }
        }
    }
    elsif $x-e.name eq 'xs:simpleType' {
        # idk
        return { simple => True };
    }
}

sub build-element($x-e) {
    my $type = $x-e<type>;
    unless $type {
        my @sub = $x-e.elements;
        if @sub[0] && @sub[0].name eq 'xs:complexType'|'xs:simpleType' {
            $type = '__p6xmls_anon_' ~ $*anon-type-count++;
            %*types{$type} = build-type(@sub[0]);
        }
    }

    return { type => $type,
             min-occurs => $x-e<minOccurs>,
             max-occurs => $x-e<maxOccurs> };
}

submethod BUILD(:$!schema!) {
    my $*anon-type-count = 1;

    my %elements;
    my %*types;

    for $!schema.elements {
        if $_.name eq 'xs:element' {
            %elements{$_<name>} = build-element($_);
        }
        if $_.name eq 'xs:complexType'|'xs:simpleType' {
            %*types{$_<name>} = build-type($_);
        }
    }

    #dd %elements;
    #dd %*types;
    %!elements = %elements;
    %!types = %*types;
}

multi method new(IO :$schema!) {
    self.new(:schema(from-xml-stream($schema)));
}

method !process-element-to-xml($name, $element, $data) {
    my @nodes;
    if !$element<type> || $element<type> ~~ /^xs\:/ {
        # builtin type
        #
        # woo *punt*
        # TODO
        @nodes.push(~$data);
    }
    else {
        my $type = %!types{$element<type>};
        die "Can't find type $type!" unless $type;
        if $type<simple> {
            # woo *punt*
            # TODO
            @nodes.push(~$data);
        }
        elsif $type<sequence>:exists {
            for $type<sequence>.list {
                # TODO: min/max occurs validation
                @nodes.push(self!process-element-to-xml($_<name>,
                                                        $_<element>,
                                                        $data{$_<name>})) if $data{$_<name>};
            }
        }
        else {
            die "Don't know how to handle complex type $type";
        }
    }
    return XML::Element.craft($name, |@nodes);
}

multi method to-xml(%data) {
    die "Please pass exactly one root element" if %data != 1;

    my $root = %data.keys.[0];
    die "Can't find $root as a top-level schema element!" if !(%!elements{$root}:exists);

    my $element = self!process-element-to-xml($root, %!elements{$root}, %data{$root});
    return XML::Document.new($element);
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
