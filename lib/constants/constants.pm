package constants::constants;

use warnings;
use strict;
use Exporter qw(import);

use constant {
	      RADIO => {id => 2, type => "radio"},
	      CHECKBOX => { id => 4, type => "checkbox"},
	      SMALL_TEXT => {id => 0, type => "text"},
	      BIG_TEXT => {id => 1, type => "text"},
	      MAX_RETRIES => 3,
	      INITIAL_DELAY => 3,
	     };
our @EXPORT = qw(RADIO CHECKBOX SMALL_TEXT BIG_TEXT MAX_RETRIES INITIAL_DELAY);

1;

