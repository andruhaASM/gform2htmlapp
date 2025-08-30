use Mojolicious::Lite;
use HTTP::Tiny;
use warnings;
use strict;
use JSON::PP;
use Data::Dumper;
use Encode qw(decode encode);
use Scalar::Util qw(reftype);


app->mode('production');

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
  my $data = $_[0];
  my $question_id = $data->[4][0][0];
  my $field_id = $data->[0];
  my $title = $data->[1];
  my $sub_title = (length $data->[2] != 0) ? "<p>$data->[2]</p>":"";
  my $is_required = ($data->[4][0][-1] == 1) ? " required":"";

  my $text_input = "
<div>
	<p><strong>$title</strong></p>
	$sub_title
	<input class=\"form-control\" type=\"text\" name=\"entry.$question_id\" id=\"id.$field_id\"$is_required>
</div> \n";

return $text_input;
}

sub parse_choice_field{
  my $data = $_[0];
  my $field_type_enum = $_[1];
  my $field_type = "";

  if ($field_type_enum == 2){
    $field_type = "radio";
  } else {
    $field_type = "checkbox";
  }

  my $question_id = $data->[4][0][0];
  my $field_id = $data->[0];
  my $title = $data->[1];
  my $sub_title = (length $data->[2] != 0) ? "<p>$data->[2]</p>":"";
  my $is_required = ($data->[4][0][-1] == 1) ? " required":"";
  my $options = $data->[4][0][1];

  my @option_values;

  for my $item (@$options){
    push(@option_values, "
<div class=\"form-check\">
	<label>
		<input class=\"form-check-input\" type=\"$field_type\"  name=\"entry.$question_id\" value=\"$item->[0]\" id=\"id.$field_id\"$is_required>
		<label class=\"form-check-label\" for=\"id.$field_id\">
		$item->[0]
		</label>
	</label>
</div>
");
 }
  my $html = "<div class=\"form-group\">\n<p><strong>$title</strong></p>$sub_title\n" . join("", @option_values) . "</div> \n";
  return $html;
}

sub extract_questions{
  my $form_data = $_[0];
  my @form_questions;
  # This is kind of fragile, because is index-based.
  # We assumed that the list of questions always will be the second element of
  # the 2nd array in the JSON returned by Google Form API.
  my $list_of_questions =  $form_data->[1][1];
  for my $item (@$list_of_questions) {
    if ($item->[3] == 0){
      my $text_field = parse_text_field($item);
      push(@form_questions, $text_field);
    } elsif ($item->[3] == 2 || $item->[3] == 4){
      my $choice_field = parse_choice_field($item, $item->[3]);
      push(@form_questions, $choice_field);
    }
  }
  # print Dumper(\@form_questions);
  my $form_html = "
<!DOCTYPE html>
<html>
<head>
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
<link href=\"https://cdn.jsdelivr.net/npm/bootstrap\@5.3.8/dist/css/bootstrap.min.css\" rel=\"stylesheet\" integrity=\"sha384-sRIl4kxILFvY47J16cr9ZwB07vP4J8+LH7qKQnuqkuIAvNWLzeN8tE5YBujZqJLB\" crossorigin=\"anonymous\">
<script src=\"https://ajax.googleapis.com/ajax/libs/jquery/3.7.1/jquery.min.js\"></script>

<title>Page Title</title>
</head>
<body>
<div class=\"container\">
<form class=\"row g-3\" id=\"customForm\">\n" . join("", @form_questions) . "<input class=\"btn btn-primary\" type=\"submit\" value=\"Enviar\">\n</form>
</div>

<script>
jQuery(function(\$) {
  \$('#customForm').on(\"submit\", function(e) {
    e.preventDefault();

    var formData = \$(this).serialize();

    \$.ajax({
      type: 'POST',
      url: \"$form_action\",
      data: formData,
      dataType: \"xml\",
      complete: function() {
      alert('Enviado com suecesso!');
      }
    });
  });
});
</script>
</body>
</html>
";
  # Remove escaped " in the final string.
  $form_html = $form_html
    =~ s/\\//gir;
  # print $form_html;
  return $form_html
}




get '/convert-google-form-to-html' => sub {
  my $c = shift;
  $c->app->log->debug("GET / called");
  $c->render('index');
};

post '/convert-google-form-to-html' => sub {
  my $c = shift;

  my $form_url = $c->param('formURL');
  $c->app->log->debug ("Form url -> $form_url \n");

  unless (length $form_url){
    return $c->render('index', error => 'Url do formulario nao pode ser vazia.');
  }
  if ($form_url !~ /.*docs\.google\.com\/forms.*/){
    $c->app->log->info("The url provided is not the Google Form URL: $form_url");
    return $c->render('index', error => 'Aceita somente Google Forms!');
   }
  if ($form_url !~ /viewform/){
    $c->app->log->info("The form is not shared publicly: $form_url");
    return $c->render('index', error => 'O formulario deve ser compartilhado publicamente.');
  }
  
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
    # print $form_action, "\n";
  }
  $extracted_form = $extracted_form
    #=~ s/null/-1/gir
    =~ s/var\sFB\_PUBLIC\_LOAD\_DATA\_\s\=\s|;$//gir;

  my $form_data = decode_json($extracted_form);
  my $result = extract_questions($form_data);

  $c->stash(form_data => $result);
  return $c->render('index', form_data => $result);
  } else {
    $c->render('index', error => "Erro ao baixar o conteudo do formulario $response->{status} $response->{reason}");
    return
}

  # unless (length $message) {
  #   $c->render('index', error => 'Message is empty');
  #   return;
  # }

  $c->redirect_to('/convert-google-form-to-html');
};

# hypnotoad does not require call to app->start.

# app->start;

# instead it needs the app to be returned.
app;

__DATA__

@@ index.html.ep
<% my $error = stash 'error'; %>

% if ($error) {
  <div style="color:red"><%= $error %></div>
    % }

<!DOCTYPE html>
<html>
<head>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css' rel='stylesheet' integrity='sha384-sRIl4kxILFvY47J16cr9ZwB07vP4J8+LH7qKQnuqkuIAvNWLzeN8tE5YBujZqJLB' crossorigin='anonymous'>
<script src='https://ajax.googleapis.com/ajax/libs/jquery/3.7.1/jquery.min.js'></script>

<title>Convert Google Form to Pure HTML.</title>
</head>
  <body>
  <div class="container">
  <div class="row">
  <h1> Converte o seu formulario 'Google Form' em puro HTML</h1>
  <p>Passo a passo:</p>
<ol class='list-group'>
  <li class='list-group-item'>Crie o formulario no Google Forms.</li>
  <li class='list-group-item'>Compartilhe o formulario publicamente.</li>
  <li class='list-group-item'>Copie e cole o URL do formulario no campo abaixo. O URL nao pode ser encurtado.</li>
  </ol>
  <div></div>
  <p> Exemplo de URL de um formulario Google Forms compartilhado publicamente:
<strong>https://docs.google.com/forms/d/e/1FAIpQLSeEZ_0EQDb5-fsbUG60hHxc-mLrBFGmYQ7YYJYyPcjYKyUX8A/viewform?usp=dialog</strong> </p>
  <p>Observações:</p>
  <ul>
  <li>Por padrao eh usado Bootstrap.</li>
  <li>Suporta somente formularios de pagina unica</li>
  <li>Tipos de perguntas que sao suportadas agora: Radio, Checkbox e texto simples</li>
  <li>Nada eh guardado no banco de dados.</li>
  <li> Codigo aberto - consulta o repositorio <a href="https://github.com/andruhaASM/gform2htmlapp" target="_blank">aqui.</a></li>
  </ul>

<form action="<%= url_for('/convert-google-form-to-html') %>" method="post">
  <b>Cole URL do Google Form aqui -></b> <%= text_field 'formURL' %> <br>
  <input class="btn btn-primary" type="submit" value="Enviar">
</form>

  <div>
  <h3>Resultado</h3>
<button type="button" class="btn btn-primary" id="copyBtn">
  Copiar HTML.
</button>
 <textarea id="autoResize" rows="1" style="overflow:hidden; resize:none;" class="form-control"><%== stash('form_data') // '' %></textarea>
  </div>
  </div>
</div>

<script>
  function autoResize(el) {
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
  }

  document.addEventListener("DOMContentLoaded", function () {
    const textarea = document.getElementById("autoResize");
    if (textarea) {
      autoResize(textarea);
      textarea.addEventListener("input", () => autoResize(textarea));
    }

    const copyBtn = document.getElementById("copyBtn");
    copyBtn.addEventListener("click", function () {
      navigator.clipboard.writeText(textarea.value)
        .then(() => {
          copyBtn.innerText = "Copiado!";
          setTimeout(() => copyBtn.innerText = "Copiar texto", 2000);
        })
        .catch(err => alert("Erro ao copiar: " + err));
    });
  });
</script>

</body>
</html>
