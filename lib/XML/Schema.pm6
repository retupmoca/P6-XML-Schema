use XML;

unit class XML::Schema;

has $.schema;

has %!elements;
has %!types;
has $!target-namespace;

multi method new(XML::Element :$schema!) {
    self.bless(:$schema);
}

multi method new(XML::Document :$schema!) {
    self.new(:schema($schema.root));
}

multi method new(Str :$schema!) {
    self.new(:schema(from-xml($schema)));
}

sub build-type($x-e) {
    if $x-e.name eq $*ns-prefix~'complexType' {
        my %ret;
        %ret<complex> = True;
        for $x-e.elements {
            if $_.name eq $*ns-prefix~'sequence' {
                my @schema-elements;
                for $_.elements {
                   @schema-elements.push((name => $_<name>,
                                          element => build-element($_)).hash);
                }
                %ret<sequence> = @schema-elements;
            }
            if $_.name eq $*ns-prefix~'attribute' {
                my %attrib;
                %attrib<name> = $_<name> if $_<name>;
                %attrib<required> = True if $_<use> && $_<use> eq 'required';
                %attrib<type> = $_<type> if $_<type>;
                %ret<attributes>.push(%attrib);
            }
        }
        return %ret;
    }
    elsif $x-e.name eq $*ns-prefix~'simpleType' {
        # idk
        return { simple => True };
    }
}

sub build-element($x-e) {
    my $type = $x-e<type>;
    my $type-ns = $x-e.nsURI() || '__DEFAULT__';
    if $type {
        if $type ~~ s/^(\w+)\:// {
            my $ns-prefix = ~$0;
            $type-ns = $x-e.nsURI($ns-prefix) || '__DEFAULT__';
        }
    }
    unless $type {
        my @sub = $x-e.elements;
        if @sub[0] && ((@sub[0].name eq $*ns-prefix~'complexType')
                    || (@sub[0].name eq $*ns-prefix~'simpleType')) {
            $type = '__p6xmls_anon_' ~ $*anon-type-count++;
            $type-ns = $*target-ns;
            %*types{$*target-ns}{$type} = build-type(@sub[0]);
            #dd %*types;
        }
    }

    my $min = $x-e<minOccurs> || 1;
    my $max = $x-e<maxOccurs> || 1;
    $max = Inf if $max ~~ m:i/^unbounded$/;

    my %ret;
    if $x-e<ref> {
        %ret<ref> = $x-e<ref> if $x-e<ref>;
        %ret<ref-namespace> = $x-e.nsURI || '__DEFAULT__';
        if %ret<ref> ~~ s/^(\w+)\:// {
            %ret<ref-namespace> = $x-e.nsURI(~$0) || '__DEFAULT__';
        }
    }
    %ret<type> = $type;
    %ret<type-namespace> = $type-ns;
    %ret<min-occurs> = $min;
    %ret<max-occurs> = $max;
    %ret<type-builtin> = True if $type && $type-ns eq 'http://www.w3.org/2001/XMLSchema';

    return %ret;
}

submethod BUILD(:$!schema!) {
    my $*anon-type-count = 1;

    my $*ns-prefix = ~$!schema.nsPrefix('http://www.w3.org/2001/XMLSchema');
    $*ns-prefix = $*ns-prefix ~ ':' if $*ns-prefix;
    my %elements;
    my %*types;

    $!target-namespace = $!schema<targetNamespace> || '__DEFAULT__';
    my $*target-ns = $!target-namespace;

    %*types{$!target-namespace} = Hash.new;

    for $!schema.elements {
        if $_.name eq $*ns-prefix~'element' {
            %elements{$!target-namespace}{$_<name>} = build-element($_);
        }
        if ($_.name eq $*ns-prefix~'complexType')
         ||($_.name eq $*ns-prefix~'simpleType') {
            %*types{$!target-namespace}{$_<name>} = build-type($_);
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

method !process-element-to-xml($name, $element is copy, $data) {
    if $element<ref> {
        my $ref = $element<ref>;
        my $ref-ns = $element<ref-namespace>;
        $element = %!elements{$ref-ns}{$ref};
    }
    my @nodes;
    if !$element<type> || $element<type-builtin> {
        # builtin type
        #
        # woo *punt*
        # TODO
        @nodes.push(~$data);
    }
    else {
        my $type = %!types{$element<type-namespace>}{$element<type>};
        die "Can't find type $element<type-namespace> - $element<type>!" unless $type;
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
    die "Can't find $root as a top-level schema element!" if !(%!elements{$!target-namespace}{$root}:exists);

    my $element = self!process-element-to-xml($root, %!elements{$!target-namespace}{$root}, %data{$root});
    return XML::Document.new($element);
}

multi method to-xml(*%data) {
    self.to-xml(%data);
}

method !process-element-from-xml($name, $element is copy, $data) {
    if $element<ref> {
        my $ref = $element<ref>;
        my $ref-ns = $element<ref-namespace>;
        $element = %!elements{$ref-ns}{$ref};
    }
    if !$element<type> || $element<type-builtin> {
        # builtin type
        #
        # woo *punt*
        # TODO
        return $data.contents.join;
    }
    else {
        my $type = %!types{$element<type-namespace>}{$element<type>};
        die "Can't find type $element<type-namespace> - $element<type>!" unless $type;
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
                my $name;
                if $_<name> {
                    $name = $_<name>;
                }
                else {
                    $name = $_<element><ref>;
                    $name = $data.nsPrefix($_<element><ref-namespace>) ~ ':' ~ $name if $_<element><ref-namespace> ne '__DEFAULT__';
                }
                while $element && $element.name eq $name {
                    my $rname = $name;
                    $rname ~~ s/^\w+\://;
                    %ret{$rname} = self!process-element-from-xml(
                                            $name,
                                            $_<element>,
                                            $element);
                    $element = @elements.shift;
                    $count++;
                }

                die "Not enough $_<name> elements!" if $count < $_<element><min-occurs>;
                die "Too many $_<name> elements!" if $count > $_<element><max-occurs>;
            }
            die "Unknown elements remaining!" if @elements;
            if $type<attributes> {
                my %seen_attrib;
                for $type<attributes>.list {
                    %seen_attrib{$_<name>}++;
                    if $data.attribs{$_<name>}:exists {
                        %ret{$_<name>} = $data.attribs{$_<name>};
                    }
                    elsif $_<required> {
                        die "Required attribute $_<name> not found!";
                    }
                }
                for $data.attribs.keys {
                    next if $_ ~~ /^xmlns/;
                    die "Unknown attribute $_!" unless %seen_attrib{$_};
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
    my $root-ns = '__DEFAULT__';
    if $root ~~ s/^(\w+)\:// {
        $root-ns = $xml.root.nsURI(~$0) || '__DEFAULT__';
    }

    die "Wrong namespace!" if $root-ns ne $!target-namespace;

    die "Can't find $root as a top-level schema element!" if !(%!elements{$!target-namespace}{$root}:exists);
    my %ret;
    %ret{$root} = self!process-element-from-xml($root,
                                                %!elements{$!target-namespace}{$root},
                                                $xml.root);
    return %ret;
}

multi method from-xml(Str $xml) {
    self.from-xml(from-xml($xml));
}

multi method from-xml(IO $xml) {
    self.from-xml(from-xml-stream($xml));
}
