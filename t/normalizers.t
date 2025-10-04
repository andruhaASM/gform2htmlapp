#!/usr/bin/perl
use lib 'lib';
use strict;
use warnings;
use Test::More tests => 1;
use JSON::PP;
use Test2::Tools::Compare;

# Modules under the test.
use normalizers::normalizers qw(normalize_common_fields normalize_small_text_field normalize_checkbox_field normalize_radio_field normalize_form_title_and_description normalize_questions);

my $form_data_as_str = '[null,["Vamos tentar coletar os dados do evento!",[[1107429416,"Bebidas",null,4,[[973230638,[["Vodka",null,null,null,0],["Gin",null,null,null,0]],1,null,null,null,null,null,0]],null,null,null,null,null,null,[null,"Bebidas"]],[322121605,"Seu nome",null,0,[[1449085720,null,1]],null,null,null,null,null,null,[null,"Seu nome"]],[639815780,"Voce eh de Floripa?",null,2,[[989928690,[["Sim",null,null,null,0],["Não",null,null,null,0]],1,null,null,null,null,null,0]],null,null,null,null,null,null,[null,"Voce eh de Floripa?"]]],null,null,null,null,null,null,"Teste",73,[null,null,null,2,null,null,1],null,null,null,null,[2],null,null,null,null,null,null,null,null,[null,"Vamos tentar coletar os dados do evento!"],[null,"Teste"]],"/forms","Teste de Parse",null,null,null,"0",null,0,0,null,"",0,"e/1FAIpQLSeEZ_0EQDb5-fsbUG60hHxc-mLrBFGmYQ7YYJYyPcjYKyUX8A",1]';

my $form_data_as_json = decode_json($form_data_as_str);
# This is derived from the form_data_as_str.
my $text_question = $form_data_as_json->[1]->[1]->[1];
print "Here is json data $text_question->[0]\n";

my %expected_normalized_small_text = (
	       question_id => '1449085720',
	       field_id => '322121605',
	       field_type => 'text',
	       title => 'Seu nome',
	       sub_title => '',
	       options => [],
	       is_required => ' required'
	      );
my $normalized_small_text = normalize_small_text_field($text_question);
print("!!!!\n\nHere is the $normalized_small_text->{question_id}\n\n\n");
is(
    $normalized_small_text,
    \%expected_normalized_small_text,
    "The normalized results for small text field are parsed as expected."
);

