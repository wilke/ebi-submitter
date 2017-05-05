#!/usr/bin/perl

# Download and create taxonomy file from NCBI for metagenome taxonomy (aka ~biom)

use strict;
use warnings;

use Data::Dumper ;
use LWP::UserAgent;
use JSON;
use Getopt::Long;
use Net::FTP;
#use XML::Simple qw(:strict);
use XML::LibXML;
  

# NCBI metagenome taxonomy
# http://www.ebi.ac.uk/ena/data/view/Taxon:410657&display=xml&download=xml&filename=410657.xml for non-host-associated.
# http://www.ebi.ac.uk/ena/data/view/Taxon:410656&display=xml&download=xml&filename=410656.xml for host-associated.


my $turl  = 'http://www.ebi.ac.uk/ena/data/view/Taxon:408169&display=xml&download=xml&filename=408169.xml' ;
my $nhurl = "http://www.ebi.ac.uk/ena/data/view/Taxon:410657&display=xml&download=xml&filename=410657.xml" ;
my $hurl  = "http://www.ebi.ac.uk/ena/data/view/Taxon:410656&display=xml&download=xml&filename=410656.xml" ;

# initialise user agent
my $ua = LWP::UserAgent->new;
$ua->agent('NCBI Taxonomy Client 0.1');


# get top level
my $response = $ua->get($turl);

unless ( $response->is_success ) {
    print STDERR "Error retrieving data\n";
    print STDERR $response->status_line, "\n";
    exit;
}

my $dom = XML::LibXML->load_xml(string => $response->content );
my $root = $dom->documentElement ;
my $type = 'none' ;

foreach my $node ($root->findnodes('//children/taxon') ) {
  my @attribs = $node->attributes();
  #print "Value:\t" , $attribs[0]->value , "\t", $attribs[1]->value , "\n" ;
  my $tmp1 = $attribs[0]->value ;
  my $tmp2 = $attribs[1]->value ;
  # my ($name)  = $attribs[0]->value =~ /scientificName="([\w\s]+) metagenome"/ ;
  # my ($taxid) = $attribs[1]->value =~ /taxId="(\d+)"/ ;
  my ($name)  = $attribs[0]->value =~ /([\w\s]+) metagenome/ ;
  my ($taxid) = $attribs[1]->value =~ /(\d+)/ ;
  #print join ("\t" , ($name || $attribs[0]->value || 'error') , 'unspecified' , $taxid || 'error' ) , "\n" ;
  print join ("\t" , ($attribs[0]->value || 'error') , 'unspecified' , $taxid || 'error' ) , "\n" ;
  &get_nodes( (undef || $attribs[0]->value || 'error') , $taxid , $ua) ;
}
exit ;


# # xml parser
#  #my $xs = XML::Simple->new(ForceArray => 1, KeepRoot => 1);
# my $type = 'non-host-associated' ;
#
# foreach my $url ( $nhurl ,$hurl ) {
#
#   my $response = $ua->get($url);
#
#   unless ( $response->is_success ) {
#       print STDERR "Error retrieving data\n";
#       print STDERR $response->status_line, "\n";
#       exit;
#   }
#
#
#
#   my $dom = XML::LibXML->load_xml(string => $response->content );
#   my $root = $dom->documentElement ;
#
#
#
#
#   # '//foo[@bar="baz"][position()<4]'
#
#
#   foreach my $node ($root->findnodes('//children/taxon') ) {
#     #print join "\t" , "Found:" , $node->nodeName , ($node->nodeValue || "none") , $node->textContent , ($node->attributes) , "\n" ;
#
#     my @attribs = $node->attributes();
#     #print "Value:\t" , $attribs[0]->value , "\t", $attribs[1]->value , "\n" ;
#     my $tmp1 = $attribs[0]->value ;
#     my $tmp2 = $attribs[1]->value ;
#     # my ($name)  = $attribs[0]->value =~ /scientificName="([\w\s]+) metagenome"/ ;
#     # my ($taxid) = $attribs[1]->value =~ /taxId="(\d+)"/ ;
#     my ($name)  = $attribs[0]->value =~ /([\w\s]+) metagenome/ ;
#     my ($taxid) = $attribs[1]->value =~ /(\d+)/ ;
#     print join ("\t" , $type , ($name || $attribs[0]->value || 'error') , $taxid || 'error' ) , "\n" ;
#   }
#
#   $type = 'host-associated' ;
#
#
# }


sub get_nodes {
  my ($type, $taxid , $ua) = @_ ;
  
  my $url = 'http://www.ebi.ac.uk/ena/data/view/Taxon:'.$taxid.'&display=xml&download=xml&filename='.$taxid.'.xml' ;
  my $response = $ua->get($url);
  
  unless ( $response->is_success ) {
      print STDERR "Error retrieving data\n";
      print STDERR $response->status_line, "\n";
      exit;
  }
  
  my $dom = XML::LibXML->load_xml(string => $response->content );
  my $root = $dom->documentElement ;
  
  foreach my $node ($root->findnodes('//children/taxon') ) {
    #print join "\t" , "Found:" , $node->nodeName , ($node->nodeValue || "none") , $node->textContent , ($node->attributes) , "\n" ;
  
    my @attribs = $node->attributes();
    #print "Value:\t" , $attribs[0]->value , "\t", $attribs[1]->value , "\n" ;
    my $tmp1 = $attribs[0]->value ;
    my $tmp2 = $attribs[1]->value ;
    # my ($name)  = $attribs[0]->value =~ /scientificName="([\w\s]+) metagenome"/ ;
    # my ($taxid) = $attribs[1]->value =~ /taxId="(\d+)"/ ;
    my ($name)  = $attribs[0]->value =~ /([\w\s]+) metagenome/ ;
    my ($taxid) = $attribs[1]->value =~ /(\d+)/ ;
    print join ("\t" , $type , ($name || $attribs[0]->value || 'error') , $taxid || 'error' ) , "\n" ;
  }
  
}


