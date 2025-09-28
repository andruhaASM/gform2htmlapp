use Mojolicious::Lite;
use HTTP::Tiny;
use warnings;
use strict;
use JSON::PP;
use Data::Dumper;
use Encode qw(decode encode);
use Scalar::Util qw(reftype);
use feature 'try';

use constant {
	      RADIO => {id => 2, type => "radio"},
	      CHECKBOX => { id => 4, type => "checkbox"},
	      SMALL_TEXT => {id => 0, type => "text"}
	     };

my %form_input_processors = (
			     RADIO->{type} => \&parse_radio_field,
			     CHECKBOX->{type} => \&parse_checkbox_field,
			     SMALL_TEXT->{type} => \&parse_text_field
			    );
my %form_input_normalizers = (
			     RADIO->{id} => \&normalize_radio_field,
			     CHECKBOX->{id} => \&normalize_checkbox_field,
			     SMALL_TEXT->{id} => \&normalize_small_text_field
			     );

my $is_prod = $ENV{"GFORM_PRODUCTION"} || 0;

if ($is_prod == 1){
  app->mode('production');
}

my $EXTRACT_FORM_ACTION_PATTERN = qr/(action="https:\/\/docs\.google\.com\/forms\/d\/e\/.*\/formResponse)/;
my $FORM_DATA_PATTERN = qr/(var\sFB\_PUBLIC\_LOAD\_DATA\_.*;)/;

my @parsed_form = ();
my $form_action = "";


sub log_something {
  my $c = shift;
  my $message = shift;
  $c->app->log->debug ("$message.\n");
}

sub normalize_common_fields{
  my $data = shift;
  my $question_id = $data->[4][0][0];
  my $field_id = $data->[0];
  my $title = $data->[1];
  my $sub_title = (length $data->[2] != 0) ? "<p>$data->[2]</p>":"";
  my $is_required = ($data->[4][0][-1] == 1) ? " required":"";
  return ($question_id, $field_id, $title, $sub_title, $is_required);
}

sub normalize_small_text_field{
  my $data = shift;
  my  ($question_id, $field_id, $title, $sub_title, $is_required) = normalize_common_fields($data);
  my $field_type = SMALL_TEXT->{type};

  my %input = (
	       question_id => $question_id,
	       field_id => $field_id,
	       field_type => $field_type,
	       title => $title,
	       sub_title => $sub_title,
	       options => [],
	       is_required => $is_required
	      );
  return \%input; # This is the recommended way to return hashes.
}

sub normalize_checkbox_field{
  my $data = shift;
  my  ($question_id, $field_id, $title, $sub_title, $is_required) = normalize_common_fields($data);
  my $field_type = CHECKBOX->{type};
  my $options = $data->[4][0][1];

  my %input = (
	       question_id => $question_id,
	       field_id => $field_id,
	       field_type => $field_type,
	       title => $title,
	       sub_title => $sub_title,
	       options => $options,
	       is_required => $is_required
	      );
  return \%input;
}

sub normalize_radio_field{
  my $data = shift;
  my  ($question_id, $field_id, $title, $sub_title, $is_required) = normalize_common_fields($data);
  my $field_type = RADIO->{type};
  my $options = $data->[4][0][1];

  my %input = (
	       question_id => $question_id,
	       field_id => $field_id,
	       field_type => $field_type,
	       title => $title,
	       sub_title => $sub_title,
	       options => $options,
	       is_required => $is_required
	      );
  return \%input;
}


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

sub get_item_type{
  # Returns the int that represents the input type.
  my $item = shift;
  my $num =  $item->[3];
  return $num;
}

sub get_list_of_questions{
  # Return the list of questions from parsed JSON.
  my $data = shift;
  my $list_of_questions =  $data->[1][1];
  # TODO: add validation if the list of questions is not empty.
  return $list_of_questions;
}

sub normalize_questions{
  # Receives a list of questions (JSON), normalizes it to a list of internal hashes and return.
  my $data = shift;
  my $normalized_questions = [];
  foreach my $item (@$data){
    my $item_type = get_item_type($item);
    # TODO: add check for the case when normalizer was not found (unsupported question type or new question).
    my $normalizer = $form_input_normalizers{$item_type};
    my $normalized_question = $normalizer->($item);
    push(@$normalized_questions, $normalized_question);
  }
  return $normalized_questions;
}



sub extract_questions{
  # Receives the list of normalized questions and transform them into HTML.
  my $data = shift;
  my $form_action = shift;
  my $c = shift;
  my $form_questions = [];
  for my $item (@$data) {
    my $item_type = $item->{field_type};
    # TODO: add check for processor. If some new questions will come and there is no processor, we have to be notified.
    my $processor = $form_input_processors{$item_type};
    my $input_content = $processor->($item, $c);
    push(@$form_questions, $input_content);
  }
  my $form_html = $c->render_to_string(
				       template => 'form_html',
				       form_questions => $form_questions,
				       form_action => $form_action,
				      );
  return $form_html
}


sub validate_form_url{
  my $form_url = shift;

  unless (length $form_url){
    return ("Url do formulario nao pode ser vazia.", "Empty form URL.");
  }
  if ($form_url !~ /.*docs\.google\.com\/forms.*/){
    return ("Aceita somente Google Forms!", "The url provided is not the Google Form URL: $form_url");
   }
  if ($form_url !~ /viewform/){
    return ("O formulario deve ser compartilhado publicamente.", "The form URL is private (was not shared publicly): $form_url.");
  }
  return ();
}

sub get_raw_html {
  # Given a validated form URL, download form HTML or log error and return empty list.
  my $form_url = shift;
  my $response = HTTP::Tiny->new->get($form_url);

  if ($response->{success}){
    return ($response->{status}, $response->{content})
  }
  return ($response->{status}, $response->{reason});
  
}

sub extract_data_from_html{
  # Get the JSON-like string and action URL from the HTML or return empty result.
  my $content = shift;
  my $form_action = "";

  my @form_protos = $content =~ $FORM_DATA_PATTERN; # this will return the list of matched parts of the string. This is the reason of accessing [0].
  # We only care about the 1st occurence.
  my $extracted_form = $form_protos[0];
  if ($content =~ $EXTRACT_FORM_ACTION_PATTERN) { # in this case (scalar context) the =~ will return true or false.
    $form_action = $1;
    # my $form_action = $1 - we cannot do this, because in perl the vars are lexically scoped. Declaring my $form_action inside a block means it lives only in that block.
    # For some reason when the form is downloaded, the action url is https://docs.google.com/forms/d/e/..., but it wont work, because the actual URL is
    # https://docs.google.com/forms/u/0/d/e/. That is why we need this regex to replace.
    $form_action = $form_action
      =~ s/action="//gir
      =~ s/\/d\/e/\/u\/0\/d\/e/gir;
  }
  $extracted_form = $extracted_form
    =~ s/var\sFB\_PUBLIC\_LOAD\_DATA\_\s\=\s|;$//gir;
  if ($form_action && $extracted_form) {
    return ($form_action, $extracted_form);
  }
  return ();
}


sub parse_to_json{
  # Try to decode the JSON-like string. Returns empty results if fails.
  my $extracted_form = shift;
  my $error;
  my $data = eval {decode_json($extracted_form)};
  my $error = $@;
  return ($error, $data);
}



get '/convert-google-form-to-html' => sub {
  my $c = shift;
  $c->app->log->debug("GET / called");
  $c->render(template => 'index');
};

post '/convert-google-form-to-html' => sub {
  my $c = shift;
  my $form_url = $c->param('formURL');
  my @validation_error_messages = validate_form_url($form_url);
  if (scalar @validation_error_messages){
    $c->app->log->info("Form URL Validation error: $validation_error_messages[1]");
    return $c->render(template => 'index', error => $validation_error_messages[0] || "Unknown error during parsing!");
  }
  $c->app->log->debug ("Downloading form with URL: $form_url \n");
  my ($status, $content) = get_raw_html($form_url);
  if ($status != 200){
    $c->app->log->debug ("Failed to fetch form with url: $form_url with status: $status and reason: $content \n");
    $c->render(template => 'index', error => "Erro ao baixar o conteudo do formulario: $status | $content.");
    return;
  }

  my ($form_action, $extracted_form) = extract_data_from_html($content);
  if (!$form_action || !$extracted_form) {
    $c->app->log->debug ("Failed extract data from raw HTML for the form with url: $form_url.\n");
    $c->render(template => 'index', error => "Erro ao extrair dados do HTML do formulario. Obs: esse app nao aceita formularios que exigem login na conta Google.\n");
    return;
  }
  my ($parsing_error, $form_data) = parse_to_json($extracted_form);
  if ($parsing_error) {
    $c->app->log->debug ("Failed to parse JSON-like string due to: $parsing_error.\n");
    $c->render(template => 'index', error => "Erro ao extrair dados do HTML do formulario.\n");
    return;
  }
  my $list_of_questions =  get_list_of_questions($form_data);
  my $normalized_questions = normalize_questions($list_of_questions);

  my $result = extract_questions($normalized_questions, $form_action, $c);

  $c->stash(form_data => $result);
  return $c->render(template => 'index', form_data => $result);

  $c->redirect_to('/convert-google-form-to-html');
};

if ($is_prod == 1){
  app;
} else {
 app->start;
}

