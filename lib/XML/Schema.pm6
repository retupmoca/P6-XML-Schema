use XML;

my sub name_split($name, $element) {
    my @parts = $name.split(/\:/);
    my $nm;
    my $ns;
    if @parts[1] {
        $nm = @parts[1];
        $ns = ~$element.nsURI(@parts[0]);
    }
    else {
        $nm = @parts[0];
        $ns = $element.nsURI ?? ~$element.nsURI !! '';
    }

    return ($ns, $nm);
}

class XML::Schema::Element { ... };
class XML::Schema::RefElement { ... };
class XML::Schema::Attribute { ... };
class XML::Schema::Group { ... };
class XML::Schema::Group::Sequence { ... };
class XML::Schema::Type { ... };
class XML::Schema::ComplexType { ... };
class XML::Schema::SimpleType { ... };

class XML::Schema {
    has $.schema;

    has %!elements;
    has %!types;
    has $.target-namespace;

    multi method new(XML::Element :$schema!) {
        self.bless(:$schema);
    }

    multi method new(XML::Document :$schema!) {
        self.new(:schema($schema.root));
    }

    multi method new(Str :$schema!) {
        self.new(:schema(from-xml($schema)));
    }

    submethod BUILD(:$!schema!) {
        $!target-namespace = $!schema<targetNamespace> || '';
    }

    multi method new(IO :$schema!) {
        self.new(:schema(from-xml-stream($schema)));
    }

    method !process-element-to-xml($schema-element, $data) {
        my @nodes;
        my $type = $schema-element.type;
        if $type ~~ XML::Schema::SimpleType {
            @nodes.push(~$data);
        }
        else {
            die "Can't find type for "~$schema-element.name unless $type;

            my %seen;
            for $type.group.parts.list {
                my $count = 0;
                if $data{$_.name}:exists {
                    %seen{$_.name}++;
                    my $items = $data{$_.name};
                    for $items.list -> $item {
                        @nodes.push(self!process-element-to-xml($_, $item));
                        $count++;
                    }
                }

                die "Not enough $_.name elements!" if $count < $_.min-occurs;
                die "Too many $_.name elements!" if $count > $_.max-occurs;
            }
            if $type.attributes {
                for $type.attributes.list {
                    if $data{$_.name}:exists {
                        %seen{$_.name}++;
                        @nodes.push($_.name => ~$data{$_.name});
                    }
                    elsif $_.required {
                        die "Required attribute $_.name not found!";
                    }
                }
            }
            for $data.keys {
                die "Data not in schema: $_!" unless %seen{$_};
            }
        }
        return XML::Element.craft($schema-element.name, |@nodes);
    }

    multi method to-xml(%data) {
        die "Please pass exactly one root element" if %data != 1;

        my $root = %data.keys.[0];
        my $element = self.get-element($.target-namespace, $root);
        die "Can't find $root as a top-level schema element!" if !$element;

        my $xml-element = self!process-element-to-xml($element, %data{$root});
        $xml-element.set('xmlns', self.target-namespace) if self.target-namespace;
        return XML::Document.new($xml-element);
    }

    multi method to-xml(*%data) {
        self.to-xml(%data);
    }

    method !process-element-from-xml($schema-element, $xml-element) {
        my $type = $schema-element.type;
        if $type ~~ XML::Schema::SimpleType {
            return $xml-element.contents.join;
        }
        my %ret;
        my @elements = $xml-element.elements;
        my $element = @elements.shift;
        my @parts = name_split($element.name, $element);
        for $type.group.parts.list {
            my $count = 0;
            while $element
                  && ((!$_.internal && @parts[0] eq $_.namespace)
                      ||($_.internal && $element.name !~~ /\:/))
                  && @parts[1] eq $_.name {
                %ret{$_.name} = self!process-element-from-xml($_, $element);
                if @elements {
                    $element = @elements.shift;
                }
                else {
                    $element = Nil;
                }
                @parts = name_split($element.name, $element) if $element;
                $count++;
            }

            die "Not enough {$_.name} elements!" if $count < $_.min-occurs;
            die "Too many {$_.name} elements (got $count)!" if $count > $_.max-occurs;
        }
        die "Unknown elements remaining!" if @elements;
        if $type.attributes {
            my %seen_attrib;
            for $type.attributes.list {
                %seen_attrib{$_.name}++;
                if $xml-element.attribs{$_.name}:exists {
                    %ret{$_.name} = $xml-element.attribs{$_.name};
                }
                elsif $_.required {
                    die "Required attribute $_.name not found!";
                }
            }
            for $xml-element.attribs.keys {
                next if $_ ~~ /^xmlns/;
                die "Unknown attribute $_!" unless %seen_attrib{$_};
            }
        }

        return %ret;
    }

    multi method from-xml(XML::Document $xml) {
        my @parts = name_split($xml.root.name, $xml.root);
        die "Wrong namespace!" if @parts[0] ne $!target-namespace;

        my $element = self.get-element(|@parts);
        die "Can't find @parts[1] as a top-level schema element!" if !$element;

        my %ret;
        %ret{@parts[1]} = self!process-element-from-xml($element, $xml.root);
        return %ret;
    }

    multi method from-xml(Str $xml) {
        self.from-xml(from-xml($xml));
    }

    multi method from-xml(IO $xml) {
        self.from-xml(from-xml-stream($xml));
    }

    method get-type($namespace, $name) {
        my $my-ns = $namespace || '__DEFAULT__';
        unless %!types{$my-ns}{$name} {
            if $my-ns eq 'http://www.w3.org/2001/XMLSchema' {
                # punt on the built-ins
                %!types{$my-ns}{$name} = XML::Schema::SimpleType.new(:$namespace);
            }
            elsif $my-ns eq ($.target-namespace || '__DEFAULT__') {
                my $xsd-ns-prefix = ~$!schema.nsPrefix('http://www.w3.org/2001/XMLSchema');
                $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;
                for $.schema.elements {
                    if $_.name eq $xsd-ns-prefix~'simpleType'
                       || $_.name eq $xsd-ns-prefix~'complexType' {
                        if $_<name> eq $name {
                            %!types{$my-ns}{$name} = XML::Schema::Type.new(:schema(self),
                                                                          :xml-element($_));
                        }
                    }
                }
            }
        }
        %!types{$my-ns}{$name};
    }

    method get-element($namespace, $name) {
        my $my-ns = $namespace || '__DEFAULT__';
        unless %!elements{$my-ns}{$name} {
            my $xsd-ns-prefix = ~$!schema.nsPrefix('http://www.w3.org/2001/XMLSchema');
            $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;
            for $.schema.elements {
                if $_.name eq $xsd-ns-prefix~'element' {
                    if $_<name> eq $name {
                        %!elements{$my-ns}{$name} = XML::Schema::Element.new(:schema(self),
                                                                            :xml-element($_));
                        last;
                    }
                }
            }
        }
        %!elements{$my-ns}{$name};
    }
};

class XML::Schema::Element {
    has $.name;
    has $.namespace;
    has $.type;
    has $.min-occurs;
    has $.max-occurs;
    has $.internal;

    method new(:$xml-element, :$schema, :$internal = False) {
        my $xsd-ns-prefix = ~$xml-element.nsPrefix('http://www.w3.org/2001/XMLSchema');
        $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;

        my $namespace = $schema.target-namespace;

        my $min = $xml-element<minOccurs> || 1;
        my $max = $xml-element<maxOccurs> || 1;
        $max = Inf if $max ~~ m:i/^unbounded$/;

        if $xml-element<ref> {
            my @parts = name_split($xml-element<ref>, $xml-element);
            return XML::Schema::RefElement.new(:ref($schema.get-element(|@parts)),
                                               :min-occurs($min),
                                               :max-occurs($max));
        }

        my $name = $xml-element<name>;

        my $type;
        my $type-name = $xml-element<type>;
        if $type-name {
            # this is a type defined...somewhere
            # but it should be global, so go look it up
            my @parts = name_split($type-name, $xml-element);
            $type = $schema.get-type(|@parts);
        }
        else {
            # anonymous type
            my @sub = $xml-element.elements;
            if @sub[0] && ((@sub[0].name eq $xsd-ns-prefix~'complexType')
                        || (@sub[0].name eq $xsd-ns-prefix~'simpleType')) {
                $type = XML::Schema::Type.new(:$schema, :xml-element(@sub[0]));
            }
        }

        return self.bless(:$namespace, :$type, :$name, :min-occurs($min), :max-occurs($max), :$internal);
    }
};
class XML::Schema::RefElement {
    has $.ref;
    has $.min-occurs;
    has $.max-occurs;
    method name { $.ref.name }
    method type { $.ref.type }
    method namespace { $.ref.namespace }
    method internal { $.ref.internal }
};
class XML::Schema::Attribute {
    has $.namespace;
    has $.name;
    has $.requred;
    has $.type;
    method new(:$xml-element, :$schema) {
        return if $xml-element<use> && $xml-element<use> eq 'prohibited';
        my $name = $xml-element<name>;

        my $namespace = $schema.target-namespace;

        my $required = False;
        $required = True if $xml-element<use> && $xml-element<use> eq 'required';

        my @parts = name_split($xml-element<type>, $xml-element);
        my $type = $schema.get-type(|@parts);
        self.bless(:$namespace, :$name, :$required, :$type);
    }
};
class XML::Schema::Group {
    has @.parts;
    method new(:$xml-element, :$schema) {
        my @parts;
        for $xml-element.elements {
           @parts.push(XML::Schema::Element.new(:$schema, :xml-element($_), :internal));
        }
        self.bless(:@parts);
    }
};
class XML::Schema::Group::Sequence is XML::Schema::Group { };
class XML::Schema::Group::Any is XML::Schema::Group { };
class XML::Schema::Group::Choice is XML::Schema::Group { };
class XML::Schema::Type {
    has $.namespace;
    multi method new(:$schema!, :$xml-element!) {
        my $xsd-ns-prefix = ~$xml-element.nsPrefix('http://www.w3.org/2001/XMLSchema');
        $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;

        my $namespace = $schema.target-namespace;

        if $xml-element.name eq $xsd-ns-prefix ~ 'simpleType' {
            return XML::Schema::SimpleType.new(:$namespace);
        }

        my $group;
        my @attributes;
        for $xml-element.elements {
            if $_.name eq $xsd-ns-prefix~'sequence' {
                $group = XML::Schema::Group::Sequence.new(:xml-element($_), :$schema);
            }
            if $_.name eq $xsd-ns-prefix~'attribute' {
                my $attribute = XML::Schema::Attribute.new(:xml-element($_), :$schema);
                @attributes.push($attribute) if $attribute;
            }
        }

        return XML::Schema::ComplexType.new(:$namespace, :$group, :@attributes);
    }
};
class XML::Schema::ComplexType is XML::Schema::Type {
    has @.attributes;
    has $.group;
};
class XML::Schema::SimpleType is XML::Schema::Type { };
