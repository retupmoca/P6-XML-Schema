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
        my %ret;
        %ret<complex> = True;
        for $x-e.elements {
            if $_.name eq 'xs:sequence' {
                my @schema-elements;
                for $_.elements {
                   @schema-elements.push((name => $_<name>,
                                          element => build-element($_)).hash);
                }
                %ret<sequence> = @schema-elements;
            }
            if $_.name eq 'xs:attribute' {
                my %attrib;
                %attrib<name> = $_<name>;
                %attrib<required> = True if $_<use> eq 'required';
                %attrib<type> = $_<type>;
                %ret<attributes>.push(%attrib);
            }
        }
        return %ret;
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

    my $min = $x-e<minOccurs> || 1;
    my $max = $x-e<maxOccurs> || 1;
    $max = Inf if $max ~~ m:i/^unbounded$/;

    return { type => $type,
             min-occurs => $min,
             max-occurs => $max };
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
            my %seen;
            for $type<sequence>.list {
                my $count = 0;
                if $data{$_<name>}:exists {
                    %seen{$_<name>}++;
                    my $items = $data{$_<name>};
                    for $items.list -> $item {
                        @nodes.push(self!process-element-to-xml(
                                           $_<name>,
                                           $_<element>,
                                           $item));
                        $count++;
                    }
                }

                die "Not enough $_<name> elements!" if $count < $_<element><min-occurs>;
                die "Too many $_<name> elements!" if $count > $_<element><max-occurs>;
            }
            if $type<attributes> {
                for $type<attributes>.list {
                    if $data{$_<name>}:exists {
                        %seen{$_<name>}++;
                        @nodes.push($_<name> => ~$data{$_<name>});
                    }
                    elsif $_<required> {
                        die "Required attribute $_<name> not found!";
                    }
                }
            }
            for $data.keys {
                die "Data not in schema: $_!" unless %seen{$_};
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

method !process-element-from-xml($name, $element, $data) {
    if !$element<type> || $element<type> ~~ /^xs\:/ {
        # builtin type
        #
        # woo *punt*
        # TODO
        return $data.contents.join;
    }
    else {
        my $type = %!types{$element<type>};
        die "Can't find type $type!" unless $type;
        if $type<simple> {
            # woo *punt*
            # TODO
            return $data.contents.join;
        }
        elsif $type<sequence>:exists {
            my %ret;
            my @elements = $data.elements;
            my $element = @elements.shift;
            for $type<sequence>.list {
                my $count = 0;
                while $element && $element.name eq $_<name> {
                    %ret{$_<name>} = self!process-element-from-xml(
                                            $_<name>,
                                            $_<element>,
                                            $element);
                    $element = @elements.shift;
                    $count++;
                }

                die "Not enough $_<name> elements!" if $count < $_<element><min-occurs>;
                die "Too many $_<name> elements!" if $count > $_<element><max-occurs>;
            }
            if $type<attributes> {
                for $type<attributes>.list {
                    if $data.attribs{$_<name>}:exists {
                        %ret{$_<name>} = $data.attribs{$_<name>};
                    }
                    elsif $_<required> {
                        die "Required attribute $_<name> not found!";
                    }
                }
            }
            return %ret;
        }
        else {
            die "Don't know how to handle complex type $type";
        }
    }
}

multi method from-xml(XML::Document $xml) {
    my $root = $xml.root.name;
    die "Can't find $root as a top-level schema element!" if !(%!elements{$root}:exists);
    my %ret;
    %ret{$root} = self!process-element-from-xml($root,
                                                %!elements{$root},
                                                $xml.root);
    return %ret;
}

multi method from-xml(Str $xml) {
    self.from-xml(from-xml($xml));
}

multi method from-xml(IO $xml) {
    self.from-xml(from-xml-stream($xml));
}
