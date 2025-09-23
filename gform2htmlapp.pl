use Mojolicious::Lite;
use HTTP::Tiny;
use warnings;
use strict;
use JSON::PP;
use Data::Dumper;
use Encode qw(decode encode);
use Scalar::Util qw(reftype);

use constant {
	      RADIO => {id => 2, type => "radio"},
	      CHECKBOX => { id => 4, type => "checkbox"},
	      SMALL_TEXT => {id => 0, type => "text"}
	     };

my $is_prod = $ENV{"GFORM_PRODUCTION"} || 0;

if ($is_prod == 1){
  app->mode('production');
}

my $pattern = qr/(var\sFB\_PUBLIC\_LOAD\_DATA\_.*;)/;
my $extract_action_pattern = qr/(action="https:\/\/docs\.google\.com\/forms\/d\/e\/.*\/formResponse)/;

my @parsed_form = ();
my $form_action = "";

sub parse_form_data{
  my $data = $_[0];
  my $temp_list = $_[1];

  if (defined $data && length $data != 0) {
    if (ref $data && reftype $data eq "ARRAY"){
      for my $item (@$data) {
	  parse_form_data($item, $temp_list);
      }
    } else {
      push(@$temp_list, $data);
    }
  }

}

sub parse_text_field{
  my ($data, $c) = @_;
  my $question_id = $data->[4][0][0];
  my $field_id = $data->[0];
  my $title = $data->[1];
  my $sub_title = (length $data->[2] != 0) ? "<p>$data->[2]</p>":"";
  my $is_required = ($data->[4][0][-1] == 1) ? " required":"";
  my $form_html = $c->render_to_string(
				       template => 'text_field',
				       question_id => $question_id,
				       field_id => $field_id,
				       title => $title,
				       sub_title => $sub_title,
				       is_required => $is_required
				      );

  return $form_html;
}

sub parse_choice_field{
  my ($data, $field_type_enum, $c)  = @_;
  my $field_type = "";

  if ($field_type_enum == RADIO->{id}){
    $field_type = RADIO->{type};
  } else {
    $field_type = CHECKBOX->{type};
  }

  my $question_id = $data->[4][0][0];
  my $field_id = $data->[0];
  my $title = $data->[1];
  my $sub_title = (length $data->[2] != 0) ? "<p>$data->[2]</p>":"";
  my $is_required = ($data->[4][0][-1] == 1) ? " required":"";
  my $options = $data->[4][0][1];
  my $form_html = $c->render_to_string(
				       template => 'choice_field',
				       field_type => $field_type,
				       options => $options,
				       question_id => $question_id,
				       field_id => $field_id,
				       title => $title,
				       sub_title => $sub_title,
				       is_required => $is_required
				      );
  return $form_html;
}

sub extract_questions{
  my ($form_data, $action, $c) = @_;
  my $form_questions = [];
  # This is kind of fragile, because is index-based.
  # We assumed that the list of questions always will be the second element of
  # the 2nd array in the JSON returned by Google Form API.
  my $list_of_questions =  $form_data->[1][1];
  for my $item (@$list_of_questions) {
    if ($item->[3] == SMALL_TEXT->{id}){
      my $text_field = parse_text_field($item, $c);
      push(@$form_questions, $text_field);
    } elsif ($item->[3] == RADIO->{id} || $item->[3] == CHECKBOX->{id}){
      my $choice_field = parse_choice_field($item, $item->[3], $c);
      push(@$form_questions, $choice_field);
    }
  }
  my $form_html = $c->render_to_string(
				       template => 'form_html',
				       form_questions => $form_questions,
				       form_action => $action,
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
  $c->app->log->debug ("Form url -> $form_url \n");
  my $response = HTTP::Tiny->new->get($form_url);

if ($response->{success}) {
  my $content = $response->{content};
  my @proto_forms = $content =~ $pattern;
  my $extracted_form = $proto_forms[0];
  if ($content =~ $extract_action_pattern) {
    $form_action = $1;
    $form_action = $form_action
      =~ s/action="//gir
      =~ s/\/d\/e/\/u\/0\/d\/e/gir;
  }
  $extracted_form = $extracted_form
    =~ s/var\sFB\_PUBLIC\_LOAD\_DATA\_\s\=\s|;$//gir;
  unless (length $extracted_form){
    return $c->render('index', error => 'Falha ao baixar o formulario. Obs: esse app nao aceita formularios que exigem login na conta Google.');
  }
  my $form_data = decode_json($extracted_form);
  my $result = extract_questions($form_data, $form_action, $c);

  $c->stash(form_data => $result);
  return $c->render(template => 'index', form_data => $result);
  } else {
    $c->render(template => 'index', error => "Erro ao baixar o conteudo do formulario $response->{status} $response->{reason}");
    return
}

  $c->redirect_to('/convert-google-form-to-html');
};

if ($is_prod == 1){
  app;
} else {
 app->start;
}

