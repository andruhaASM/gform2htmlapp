package constants::constants;

use warnings;
use strict;
use Exporter qw(import);

use constant {
	      RADIO => {id => 2, type => "radio"},
	      CHECKBOX => { id => 4, type => "checkbox"},
	      SMALL_TEXT => {id => 0, type => "text"}
	     };
our @EXPORT = qw(RADIO CHECKBOX SMALL_TEXT);

1;
