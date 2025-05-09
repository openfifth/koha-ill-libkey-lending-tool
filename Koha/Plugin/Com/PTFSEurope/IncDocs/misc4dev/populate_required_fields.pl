
use Try::Tiny;
use C4::Context;

use Koha::Patron::Attribute::Type;
use Koha::Patron::Attributes;
use Koha::Patron::Attributes;
use Koha::AdditionalField;

my $ill_partner_category = C4::Context->preference('ILLPartnerCode') || 'IL';

try {
    Koha::Patron::Attribute::Type->new(
        {
            code          => 'incdocs_id',
            description   => 'This record\'s ID in IncDocs',
            class         => 'IncDocs',
            unique_id     => 1,
            category_code => $ill_partner_category
        }
    )->store;
} catch {
    print "Error: $_\n";
};

try {
    Koha::AdditionalField->new(
        {
            tablename      => 'branches',
            name           => 'incdocs_id',
        }
    )->store;
} catch {
    print "Error: $_\n";
};

1;
