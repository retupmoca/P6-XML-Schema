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
    has %!groups;
    has $.target-namespace;
    has $.qualified-elements;
    has $.qualified-attributes;

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
        $!qualified-elements = False;
        $!qualified-elements = True if $!schema<elementFormDefault>
                                    && $!schema<elementFormDefault> eq 'qualified';
        $!qualified-attributes = False;
        $!qualified-attributes = True if $!schema<attributeFormDefault>
                                      && $!schema<attributeFormDefault> eq 'qualified';
    }

    multi method new(IO :$schema!) {
        self.new(:schema(from-xml-stream($schema)));
    }

    multi method to-xml(%data) {
        die "Please pass exactly one root element" if %data != 1;

        my $root = %data.keys.[0];
        my $element = self.get-element($.target-namespace, $root);
        die "Can't find $root as a top-level schema element!" if !$element;

        my $xml-element = $element.to-xml(%data{$root});
        $xml-element.set('xmlns', self.target-namespace) if self.target-namespace;
        return XML::Document.new($xml-element);
    }

    multi method to-xml(*%data) {
        self.to-xml(%data);
    }

    multi method from-xml(XML::Document $xml) {
        my @parts = name_split($xml.root.name, $xml.root);
        die "Wrong namespace!" if @parts[0] ne $!target-namespace;

        my $element = self.get-element(|@parts);
        die "Can't find @parts[1] as a top-level schema element!" if !$element;

        my %ret;
        %ret{@parts[1]} = $element.from-xml($xml.root);
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

    method get-group($id) {
        unless %!groups{$id} {
            my $element = $!schema.getElementById($id);
            $element = $element.elements.[0];
            my $xsd-ns-prefix = ~$element.nsPrefix('http://www.w3.org/2001/XMLSchema');
            $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;
            if $element.name eq $xsd-ns-prefix~'sequence' {
                %!groups{$id} = XML::Schema::Group::Sequence.new(:schema(self), :xml-element($element));
            }
            if $element.name eq $xsd-ns-prefix~'choice' {
                %!groups{$id} = XML::Schema::Group::Choice.new(:schema(self), :xml-element($element));
            }
        }
        return %!groups{$id};
    }
};

class XML::Schema::Element {
    has $.name;
    has $.namespace;
    has $.type;
    has $.min-occurs;
    has $.max-occurs;
    has $.internal;
    has $.qualified;
    has $.nillable;

    method new(:$xml-element, :$schema, :$internal = False) {
        my $xsd-ns-prefix = ~$xml-element.nsPrefix('http://www.w3.org/2001/XMLSchema');
        $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;

        my $namespace = $schema.target-namespace;
        my $qualified = False;
        $qualified = True if $xml-element<form> && $xml-element<form> eq 'qualified';
        my $nillable = False;
        $nillable = True if $xml-element<nillable> && $xml-element<nillable> eq 'true';

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

        return self.bless(:$namespace,
                          :$type,
                          :$name,
                          :$qualified,
                          :min-occurs($min),
                          :max-occurs($max),
                          :$internal);
    }

    method from-xml($xml-element) {
        return self.type.from-xml($xml-element);
    }

    method to-xml($data) {
        my @nodes = self.type.to-xml($data);
        return XML::Element.craft(self.name, |@nodes);
    }
};
class XML::Schema::RefElement {
    has $.ref handles <name type namespace internal qualified from-xml>;
    has $.min-occurs;
    has $.max-occurs;
};
class XML::Schema::Attribute {
    has $.namespace;
    has $.name;
    has $.requred;
    has $.type;
    has $.qualified;
    method new(:$xml-element, :$schema) {
        return if $xml-element<use> && $xml-element<use> eq 'prohibited';
        my $name = $xml-element<name>;

        my $qualified = False;
        $qualified = True if $xml-element<form> && $xml-element<form> eq 'qualified';

        my $namespace = $schema.target-namespace;

        my $required = False;
        $required = True if $xml-element<use> && $xml-element<use> eq 'required';

        my @parts = name_split($xml-element<type>, $xml-element);
        my $type = $schema.get-type(|@parts);
        self.bless(:$namespace, :$name, :$required, :$type, :$qualified);
    }
};
class XML::Schema::Group {
    has @.parts;
    has $.schema;
    multi method new(:$xml-element!, :$schema!) {
        my $xsd-ns-prefix = ~$xml-element.nsPrefix('http://www.w3.org/2001/XMLSchema');
        $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;
        my @parts;
        for $xml-element.elements {
            if $_.name eq $xsd-ns-prefix~'element' {
                @parts.push(XML::Schema::Element.new(:$schema, :xml-element($_), :internal));
            }
            if $_.name eq $xsd-ns-prefix~'sequence' {
                @parts.push: XML::Schema::Group::Sequence.new(:xml-element($_), :$schema);
            }
            if $_.name eq $xsd-ns-prefix~'choice' {
                @parts.push: XML::Schema::Group::Choice.new(:xml-element($_), :$schema);
            }
            if $_.name eq $xsd-ns-prefix~'group' && $_<ref> {
                @parts.push: XML::Schema::Group::Reference.new(:ref($schema.get-group($_<ref>)));
            }
        }
        self.bless(:@parts, :$schema);
    }
    method from-xml(@elements) { ... }
    method to-xml($data, :%seen) {
        my @nodes;
        for self.parts.list {
            when XML::Schema::Group {
                @nodes.append: $_.to-xml($data, :%seen);
            }
            when XML::Schema::Element|XML::Schema::RefElement {
                my $count = 0;
                if $data{$_.name}:exists {
                    %seen{$_.name}++;
                    my $items = $data{$_.name};
                    for $items.list -> $item {
                        @nodes.push($_.to-xml($item));
                        $count++;
                    }
                }

                die "Not enough $_.name elements!" if $count < $_.min-occurs;
                die "Too many $_.name elements!" if $count > $_.max-occurs;
            }
        }
        return @nodes;
    }
};
class XML::Schema::Group::Reference is XML::Schema::Group {
    has $.ref handles <from-xml to-xml>;
}
class XML::Schema::Group::Sequence is XML::Schema::Group {
    method from-xml(@elements) {
        my %ret;
        for self.parts.list {
            when XML::Schema::Group {
                my %tmp = $_.from-xml(@elements);
                for %tmp.kv -> $k, $v {
                    %ret{$k} = $v;
                }
            }
            when XML::Schema::Element|XML::Schema::RefElement {
                my $need-ns = !$_.internal || $_.qualified || $.schema.qualified-elements;
                my $count = 0;
                my @ret;
                my $element = @elements ?? @elements.shift !! Nil;
                my @parts = name_split($element.name, $element) if $element;
                while $element
                      && (($need-ns && @parts[0] eq $_.namespace)
                          ||(!$need-ns && $element.name !~~ /\:/))
                      && @parts[1] eq $_.name {
                    @ret.push($_.from-xml($element));
                    $element = @elements ?? @elements.shift !! Nil;
                    @parts = name_split($element.name, $element) if $element;
                    $count++;
                }
                @elements.unshift($element) if $element;
                if @ret {
                    if $_.max-occurs == 1 {
                        %ret{$_.name} = @ret[0];
                    }
                    else {
                        %ret{$_.name} = @ret;
                    }
                }

                die "Not enough {$_.name} elements!" if $count < $_.min-occurs;
                die "Too many {$_.name} elements (got $count)!" if $count > $_.max-occurs;
            }
        }
        return %ret;
    }
};
class XML::Schema::Group::All is XML::Schema::Group {
    method from-xml(@elements) {
        ...
    }
};
class XML::Schema::Group::Choice is XML::Schema::Group {
    method from-xml(@elements) {
        my %ret;
        for self.parts.list {
            my @tmp = @elements;
            when XML::Schema::Group {
                %ret = $_.from-xml(@elements);
                return %ret;
                CATCH {
                    default {
                        # move along
                    }
                }
            }
            when XML::Schema::Element|XML::Schema::RefElement {
                my $need-ns = !$_.internal || $_.qualified || $.schema.qualified-elements;
                my $count = 0;
                my @ret;
                my $element = @elements.shift;
                my @parts = name_split($element.name, $element);
                while $element
                      && (($need-ns && @parts[0] eq $_.namespace)
                          ||(!$need-ns && $element.name !~~ /\:/))
                      && @parts[1] eq $_.name {
                    @ret.push($_.from-xml($element));
                    if @elements {
                        $element = @elements.shift;
                    }
                    else {
                        $element = Nil;
                    }
                    @parts = name_split($element.name, $element) if $element;
                    $count++;
                }
                if @ret {
                    if $_.max-occurs == 1 {
                        %ret{$_.name} = @ret[0];
                    }
                    else {
                        %ret{$_.name} = @ret;
                    }
                }
                return %ret if $count;
            }
            @elements = @tmp;
        }
        die "None of the 'choice' parts were found!";
    }
    method to-xml($data, :%seen) {
        my @nodes;
        for self.parts.list {
            when XML::Schema::Group {
                my %s = %seen;
                @nodes.append: $_.to-xml($data, :%seen);
                return @nodes;
                CATCH {
                    default {
                        %seen = %s;
                    }
                }
            }
            when XML::Schema::Element|XML::Schema::RefElement {
                my $count = 0;
                if $data{$_.name}:exists {
                    %seen{$_.name}++;
                    my $items = $data{$_.name};
                    for $items.list -> $item {
                        @nodes.push($_.to-xml($item));
                        $count++;
                    }
                }

                return @nodes if $count;
            }
        }
        die "None of the 'choice' parts were found!";
    }
};
class XML::Schema::Type {
    has $.namespace;
    has $.schema;
    multi method new(:$schema!, :$xml-element!) {
        my $xsd-ns-prefix = ~$xml-element.nsPrefix('http://www.w3.org/2001/XMLSchema');
        $xsd-ns-prefix ~= ':' if $xsd-ns-prefix;

        my $namespace = $schema.target-namespace;

        if $xml-element.name eq $xsd-ns-prefix ~ 'simpleType' {
            return XML::Schema::SimpleType.new(:$namespace, :$schema);
        }

        my $group;
        my @attributes;
        for $xml-element.elements {
            if $_.name eq $xsd-ns-prefix~'sequence' {
                $group = XML::Schema::Group::Sequence.new(:xml-element($_), :$schema);
            }
            if $_.name eq $xsd-ns-prefix~'choice' {
                $group = XML::Schema::Group::Choice.new(:xml-element($_), :$schema);
            }
            if $_.name eq $xsd-ns-prefix~'all' {
                $group = XML::Schema::Group::All.new(:xml-element($_), :$schema);
            }
            if $_.name eq $xsd-ns-prefix~'attribute' {
                my $attribute = XML::Schema::Attribute.new(:xml-element($_), :$schema);
                @attributes.push($attribute) if $attribute;
            }
        }

        return XML::Schema::ComplexType.new(:$namespace, :$group, :@attributes, :$schema);
    }
};
class XML::Schema::ComplexType is XML::Schema::Type {
    has @.attributes;
    has $.group;
    method from-xml($xml-element) {
        my @elements = $xml-element.elements;
        my %ret = self.group.from-xml(@elements);
        die "Extra elements!" if @elements;
        if self.attributes {
            my %seen_attrib;
            for self.attributes.list {
                my $need-ns = $_.qualified || $.schema.qualified-attributes;
                my $lookup = $_.name;
                if $need-ns {
                    my $ns-prefix = ~$xml-element.nsPrefix($_.namespace) || '';
                    $lookup = $ns-prefix ~ ':' ~ $lookup if $ns-prefix;
                }
                %seen_attrib{$lookup}++;
                if $xml-element.attribs{$lookup}:exists {
                    %ret{$_.name} = $xml-element.attribs{$lookup};
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
    method to-xml($data) {
        my @nodes;

        my %seen;
        @nodes.append: self.group.to-xml($data, :%seen);
        if self.attributes {
            for self.attributes.list {
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
        return @nodes;
    }
};
class XML::Schema::SimpleType is XML::Schema::Type {
    method from-xml($xml-element) {
        return $xml-element.contents.join;
    }
    method to-xml($data) {
        my @nodes;
        @nodes.push(~$data);
        return @nodes;
    }
};
