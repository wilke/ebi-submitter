#!/usr/bin/env perl

# Create taxonomy file from shock node

use strict;
use warnings;

use Data::Dumper;
use JSON;

use Getopt::Long;


# Files to compare - json
my $shock_attributes      = undef ;

# Example of shock attributes file:
#
# {
#    "status" : 200,
#    "error" : null,
#    "data" : {
#        ...
#        "attributes" : {
#           "type" : "ontology",
#           "showRoot" : false,
#           "rootNode" : "Taxonomy:408169",
#           "nodeCount" : 258,
#           "version" : "latest",
#           "name" : "metagenome_taxonomy"
#        },
#        ...
#        "last_modified" : "2017-05-18T16:03:54.537-05:00",
#        ...
#     }
# }

my $taxonoomy_nodes_file  = undef ;

# Format of nodes file
# {
#   Taxonomy:1954208 : {
#     "parentNodes" : [
#              "Taxonomy:410657"
#           ],
#           "childNodes" : [],
#           "id" : "Taxonomy:1954208",
#           "label" : "oil",
#           "description" : ""
#     },
#   ....
# }

# Options
my $help          = 0 ;
my $attributes    = undef ;
my $file          = undef ;

# initialize json 
my $json = new JSON ;

# Set command line options
GetOptions(
     'help'         => \$help,
     'attributes=s' => \$attributes ,
     'nodes=s'      => \$file,
     );

if ($help) {
  print "Usage: $0 -help -attributes <FILE> -nodes <FILE>\n" ;
  exit;
}

my $taxa = undef ;

if (-f $attributes and -f $file){

  # Load attributes
  open(ATTR , "$attributes") or die "Can't open file $attributes\n";
  
  my $tmp = '' ;
  while (my $line = <ATTR>){
    $tmp .= $line ;
  }
  my $shock_attr = $json->decode($tmp) ; 
  $taxa  = $shock_attr->{data}->{attributes} ;  
  
  close ATTR ;
  
  # Load nodes
  open(NODES , "$file") or die "Can't open file $file\n";
  
  $tmp = '' ; # clear tmp
  while (my $line = <NODES>){
    $tmp .= $line ;
  }
  my $nodes = $json->decode($tmp) ; 
  $taxa->{nodes}  = $nodes ;  
  
  close NODES ;
  
  print $json->encode($taxa) ;
  
}
else{
  print STDERR "Missing file for attributes or nodes.\n" ;
}




     