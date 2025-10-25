package normalizers::normalizers;

use lib 'lib';
use strict;
use warnings;
use Exporter qw(import);
use constants::constants qw(RADIO CHECKBOX SMALL_TEXT BIG_TEXT);

our @EXPORT = qw(normalize_common_fields normalize_small_text_field normalize_checkbox_field normalize_radio_field normalize_form_title_and_description normalize_questions);

my %form_input_normalizers = (
			     RADIO->{id} => \&normalize_radio_field,
			     CHECKBOX->{id} => \&normalize_checkbox_field,
			     SMALL_TEXT->{id} => \&normalize_text_field,
			     BIG_TEXT->{id} => \&normalize_text_field
			     );


sub get_item_type{
  # Returns the int that represents the input type.
  my $item = shift;
  my $num =  $item->[3];
  return $num;
}

sub normalize_common_fields{
  my $data = shift;
  my $question_id = $data->[4][0][0];
  my $field_id = $data->[0];
  my $title = $data->[1];
  my $gform_int_id = $data->[3];
  my $sub_title = (length $data->[2] != 0) ? "<p>$data->[2]</p>":"";
  my $is_required = ($data->[4][0][-1] == 1) ? " required":"";
  return ($question_id, $field_id, $title, $sub_title, $is_required, $gform_int_id);
}

sub normalize_text_field{
  my $data = shift;
  my  ($question_id, $field_id, $title, $sub_title, $is_required, $gform_int_id) = normalize_common_fields($data);
  my $field_type = SMALL_TEXT->{type};

  my %input = (
	       question_id => $question_id,
	       field_id => $field_id,
	       field_type => $field_type,
	       gform_int_id => $gform_int_id,
	       title => $title,
	       sub_title => $sub_title,
	       options => [],
	       is_required => $is_required
	      );
  return \%input; # This is the recommended way to return hashes.
}

sub normalize_checkbox_field{
  my $data = shift;
  my  ($question_id, $field_id, $title, $sub_title, $is_required, $gform_int_id) = normalize_common_fields($data);
  my $field_type = CHECKBOX->{type};
  my $options = $data->[4][0][1];

  my %input = (
	       question_id => $question_id,
	       field_id => $field_id,
	       field_type => $field_type,
	       gform_int_id => $gform_int_id,
	       title => $title,
	       sub_title => $sub_title,
	       options => $options,
	       is_required => $is_required
	      );
  return \%input;
}

sub normalize_radio_field{
  my $data = shift;
  my  ($question_id, $field_id, $title, $sub_title, $is_required, $gform_int_id) = normalize_common_fields($data);
  my $field_type = RADIO->{type};
  my $options = $data->[4][0][1];

  my %input = (
	       question_id => $question_id,
	       field_id => $field_id,
	       field_type => $field_type,
	       gform_int_id => $gform_int_id,
	       title => $title,
	       sub_title => $sub_title,
	       options => $options,
	       is_required => $is_required
	      );
  return \%input;
}


sub normalize_form_title_and_description {
  my $data = shift;
  my $c = shift;
  my $form_title = $data->[1]->[8];
  my $form_description = $data->[1]->[0];
  my %title_description = (
	       title => $form_title,
	       description => $form_description
			  );
  return \%title_description;
}

sub normalize_questions{
  # Receives a list of questions (JSON), normalizes it to a list of internal hashes and return.
  my $data = shift;
  my $normalized_questions = [];
  foreach my $item (@$data){
    my $item_type = get_item_type($item);
    # TODO: add check for the case when normalizer was not found (unsupported question type or new question).
    my $normalizer = $form_input_normalizers{$item_type};
    if (!$normalizer){
      next;
    }
    my $normalized_question = $normalizer->($item);
    push(@$normalized_questions, $normalized_question);
  }
  return $normalized_questions;
}

1;

