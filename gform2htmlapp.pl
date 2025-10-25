use lib 'lib';
use Mojolicious::Lite;
use HTTP::Tiny;
use warnings;
use strict;
use Data::Dumper;
use Encode qw(decode encode);
use Scalar::Util qw(reftype);
use UUID::Tiny ':std';

use Data::Dumper;

# Custom modules

use parsers::parsers qw(parse_text_field parse_big_text_field parse_checkbox_field parse_radio_field parse_title_and_description parse_to_json);
use normalizers::normalizers qw(normalize_common_fields normalize_small_text_field normalize_checkbox_field normalize_radio_field normalize_form_title_and_description normalize_questions);
# use normalizers::normalizers qw(normalize_questions normalize_form_title_and_description);
use constants::constants qw(RADIO CHECKBOX SMALL_TEXT BIG_TEXT MAX_RETRIES INITIAL_DELAY);

my %form_input_processors = (
			     RADIO->{id} => \&parse_radio_field,
			     CHECKBOX->{id} => \&parse_checkbox_field,
			     SMALL_TEXT->{id} => \&parse_text_field,
			     BIG_TEXT->{id} => \&parse_big_text_field
			    );
my %local_cache;

my $is_prod = $ENV{"GFORM_PRODUCTION"} || 0;

if ($is_prod == 1){
  app->mode('production');
}

my $EXTRACT_FORM_ACTION_PATTERN = qr/(action="https:\/\/docs\.google\.com\/forms\/d\/e\/.*\/formResponse)/;
my $FORM_DATA_PATTERN = qr/(var\sFB\_PUBLIC\_LOAD\_DATA\_.*;)/;

my @parsed_form = ();


sub log_something {
  my $c = shift;
  my $message = shift;
  $c->app->log->debug ("$message.\n");
}

sub get_list_of_questions{
  # Return the list of questions from parsed JSON.
  my $data = shift;
  my $list_of_questions =  $data->[1][1];
  # TODO: add validation if the list of questions is not empty.
  return $list_of_questions;
}


sub render_form{
  # Receives form title and descriptio and the list of questions and transform them into HTML.
  my $questions = shift;
  my $form_action = shift;
  my $title_and_description = shift;
  my $c = shift;
  my $form_questions = [];
  for my $item (@$questions) {
    my $item_type = $item->{gform_int_id};
    # TODO: add check for processor. If some new questions will come and there is no processor, we have to be notified.
    my $processor = $form_input_processors{$item_type};
    if(!$processor){
      next;
    }
    my $input_content = $processor->($item, $c);
    push(@$form_questions, $input_content);
  }
  my $form_html = $c->render_to_string(
				       template => 'form_html',
				       title_and_description => $title_and_description,
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
  my $c = shift;
  my $response;
  my $success = 0;
  my $current_attempt = 1;
  my $initial_delay = INITIAL_DELAY;
  while ($current_attempt <= MAX_RETRIES){
    $@ = '';
    eval {
      $c->app->log->debug("Attempting to fetch URL: $form_url. Attempt #$current_attempt");
      $response = HTTP::Tiny->new->get($form_url);
      die "Error when fetching form URL: $form_url."
	unless $response->{success};
    };
  if ($@){
    $c->app->log->debug("Failed to fetch URL: $form_url with error: $@ on attempt #$current_attempt.");
    sleep($initial_delay);
    $current_attempt++;
    $initial_delay *= 2;
  } else {
    $success = 1;
    last;
  }
  }
  unless ($success){
    $c->app->log->debug("Failed to fetch URL: $form_url with error: $@.");
  }

  if ($response->{success}){
    return ($response->{status}, $response->{content}, $current_attempt)
  }
  return ($response->{status}, $response->{reason}, $current_attempt);
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



get '/convert-google-form-to-html' => sub {
  my $c = shift;
  my $form_data_id = $c->flash('form_data_id');
  my $form_data =  $local_cache{$form_data_id};
  delete $local_cache{$form_data_id};
  my $error = $c->flash("error");
  return $c->render(template => 'index', form_data => $form_data, error => $error);
};

post '/convert-google-form-to-html' => sub {
  my $c = shift;
  my $form_url = $c->param('formURL');
  my $unique_form_id  = create_uuid_as_string(UUID_V4);
  my @validation_error_messages = validate_form_url($form_url);
  if (scalar @validation_error_messages){
    $c->app->log->info("Form URL Validation error: $validation_error_messages[1]");
    $c->flash(error =>  $validation_error_messages[0]);
    return $c->redirect_to("/convert-google-form-to-html");
  }
  $c->app->log->debug ("Downloading form with URL: $form_url \n");
  my ($status, $content, $attempts) = get_raw_html($form_url, $c);
  if ($status != 200){
    $c->app->log->debug ("Failed to fetch form with url: $form_url with status: $status and reason: $content \n");
    $c->flash(error => "Erro ao baixar o conteudo do formulario depois de $attempts tentativas: $status | $content.");
    return $c->redirect_to("/convert-google-form-to-html");
  }

  my ($form_action, $extracted_form) = extract_data_from_html($content);
  if (!$form_action || !$extracted_form) {
    $c->app->log->debug ("Failed extract data from raw HTML for the form with url: $form_url.\n");
    $c->flash(error => "Erro ao extrair dados do HTML do formulario. Obs: esse app nao aceita formularios que exigem login na conta Google.\n");
     return $c->redirect_to("/convert-google-form-to-html");
  }
  my ($parsing_error, $form_data) = parse_to_json($extracted_form);
  if ($parsing_error) {
    $c->app->log->debug ("Failed to parse JSON-like string due to: $parsing_error.\n");
    $c->flash(error => "Erro ao extrair dados do HTML do formulario.\n");
    return $c->redirect_to("/convert-google-form-to-html");
  }
  my $list_of_questions =  get_list_of_questions($form_data);
  my $normalized_form_title_and_description = normalize_form_title_and_description($form_data, $c);
  my $title_and_description = parse_title_and_description($normalized_form_title_and_description, $c);
  my $normalized_questions = normalize_questions($list_of_questions, $c);

  my $result = render_form($normalized_questions, $form_action, $title_and_description, $c);
  $local_cache{$unique_form_id} = $result;
  # Post -> Redirect -> Get patterns.
  $c->flash(form_data_id => $unique_form_id);
  return $c->redirect_to("/convert-google-form-to-html");
};

if ($is_prod == 1){
  app;
} else {
 app->start;
}

