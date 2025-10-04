package parsers::parsers;

use strict;
use warnings;
use Exporter qw(import);
use JSON::PP;

# The @EXPORT list both defines which symbols are available for importing (the public
# interface) and provides a default list for Perl to use when we don’t specify an import
# list.
our @EXPORT = qw(parse_text_field parse_checkbox_field parse_radio_field parse_title_and_description parse_to_json);
# What if we had subroutines we didn’t want as part of the default import but would still
# be available if we asked for them? We can add those subroutines to the @EXPORT_OK
# list in the module’s package.


sub parse_text_field{
  my $normalized_data = shift;
  my $c = shift;
  my $form_html = $c->render_to_string(
				       template => 'text_field',
				       question_id => $normalized_data->{question_id},
				       field_id => $normalized_data->{field_id},
				       title => $normalized_data->{title},
				       sub_title => $normalized_data->{sub_title},
				       is_required => $normalized_data->{is_required}
				      );

  return $form_html;
}

sub parse_checkbox_field{
  my $normalized_data = shift;
  my $c  = shift;
  my $form_html = $c->render_to_string(
				       template => 'choice_field',
				       field_type => $normalized_data->{field_type},
				       options => $normalized_data->{options},
				       question_id => $normalized_data->{question_id},
				       field_id => $normalized_data->{field_id},
				       title => $normalized_data->{title},
				       sub_title => $normalized_data->{sub_title},
				       is_required => $normalized_data->{is_required}
				      );
  return $form_html;
}


sub parse_radio_field{
  my $normalized_data = shift;
  my $c  = shift;
  my $form_html = $c->render_to_string(
				       template => 'choice_field',
				       field_type => $normalized_data->{field_type},
				       options => $normalized_data->{options},
				       question_id => $normalized_data->{question_id},
				       field_id => $normalized_data->{field_id},
				       title => $normalized_data->{title},
				       sub_title => $normalized_data->{sub_title},
				       is_required => $normalized_data->{is_required}
				      );
  return $form_html;
}

sub parse_title_and_description{
  my $normalized_data = shift;
  my $c = shift;

  my $form_html = $c->render_to_string(
				       template => 'title_description',
				       title => $normalized_data->{title},
				       description => $normalized_data->{description}
				      );
  return $form_html;
}

sub parse_to_json{
  # Try to decode the JSON-like string. Returns empty results if fails.
  my $extracted_form = shift;
  my $data = eval {decode_json($extracted_form)};
  my $error = $@;
  return ($error, $data);
}

1;

