#!/usr/bin/perl

# Download and create taxonomy file from NCBI for metagenome taxonomy (aka ~biom)

use strict;
use warnings;

use Data::Dumper;
use LWP::UserAgent;
use JSON;

use Getopt::Long;
use Net::FTP;

#use XML::Simple qw(:strict);
use XML::LibXML;
use XML::XML2JSON;

# NCBI metagenome taxonomy
# http://www.ebi.ac.uk/ena/data/view/Taxon:410657&display=xml&download=xml&filename=410657.xml for non-host-associated.
# http://www.ebi.ac.uk/ena/data/view/Taxon:410656&display=xml&download=xml&filename=410656.xml for host-associated.

my $turl =
'http://www.ebi.ac.uk/ena/data/view/Taxon:408169&display=xml&download=xml&filename=408169.xml';
# my $nhurl =
# "http://www.ebi.ac.uk/ena/data/view/Taxon:410657&display=xml&download=xml&filename=410657.xml";
# my $hurl =
# "http://www.ebi.ac.uk/ena/data/view/Taxon:410656&display=xml&download=xml&filename=410656.xml";

# initialise user agent
my $ua = LWP::UserAgent->new;
$ua->agent('NCBI Taxonomy Client 0.1');



# Create flat list
&create_flat_list($ua);


# Create json
# Walk through all nodes , add synonyms to description field
&create_json_list($ua);


exit;


# Create flat list
sub create_flat_list {
 my ($ua) = @_ ; 
 
 # get top level
 my $response = $ua->get($turl);

 unless ( $response->is_success ) {
     print STDERR "Error retrieving data\n";
     print STDERR $response->status_line, "\n";
     exit;
 }

 my $dom  = XML::LibXML->load_xml( string => $response->content );
 my $root = $dom->documentElement;
 my $type = 'none';

 open(TSV , ">taxonomy.tsv") or die "Can't open file for writing!\n" ;


 foreach my $node ( $root->findnodes('//children/taxon') ) {
     my @attribs = $node->attributes();

     my ($name)  = $attribs[0]->value =~ /([\w\s]+) metagenome/;
     my ($taxid) = $attribs[1]->value =~ /(\d+)/;

     
     print TSV join( "\t",
         ( $attribs[0]->value || 'error' ),
         'unspecified', $taxid || 'error' ),
       "\n";
     &get_nodes( ( undef || $attribs[0]->value || 'error' ), $taxid, $ua );
 }
 
 close TSV ; 
}


# Create json
# Walk through all nodes , add synonyms to description field
sub create_json_list {
   my ($ua) = @_ ; 
   
   my $response = $ua->get($turl);

   unless ( $response->is_success ) {
       print STDERR "Error retrieving data\n";
       print STDERR $response->status_line, "\n";
       exit;
   }

   my $dom  = XML::LibXML->load_xml( string => $response->content );
   my $root = $dom->documentElement;
   my $type = 'none';

   # my $XML2JSON = XML::XML2JSON->new();
   # my $JSON = $XML2JSON->convert($response->content);
   # print $JSON;

   print $root->nodeName, ":\n";

   # my $node = {
   #   parentNodes => [] ,
   #   childNodes  => [] ,
   #   description => '' ,
   #   id          => '' ,
   #   label       => '' ,
   # };

   # get download date
   my $time = gmtime() ;
   $time =~ s/(\d\d\d\d)$/UTC $1/ ; 
   
   # build version number from date
   my $version = `date "+%Y-%m-%d"` ;
   chomp($version) ; 
   
  


   my $data = {
       "nodes"    => {},
       "version"  => "$version",
       "download" => {
           "date" => $time ,
           "url"  => "http://www.ebi.ac.uk/ena/data/view/Taxon:408169&display=xml",
       },
       "rootNode" => 'Taxonomy:408169',
       "name"     => "metagenome_taxonomy",
       "type"     => "ontology",    # "taxonomy"
       "description" => "Metagenome subtree from EBI Taxonomy (http://www.ebi.ac.uk/ena/data/view/Taxon:408169) ",
       "showRoot" => JSON::false,
   };


   &createNode( $data, undef, "408169" );
   print Dumper $data;

   my $json = JSON->new->allow_nonref;

   open(File , ">taxonomy.json") or die "Can't open file for writing!\n" ;
   print File $json->encode($data);
   close File;
}



sub createNode {
    my ( $data, $parent, $taxid ) = @_;

    # if ($parent) {
 #        print Dumper $parent;
 #
 #        #exit;
 #    }

    # Get taxon node
    my $url =
      'http://www.ebi.ac.uk/ena/data/view/Taxon:' . $taxid . '&display=xml';
    my $response = $ua->get($url);

    unless ( $response->is_success ) {
        print STDERR "Error retrieving data\n";
        print STDERR $response->status_line, "\n";
        exit;
    }

    my $dom  = XML::LibXML->load_xml( string => $response->content );
    my $root = $dom->documentElement;
    my $type = 'none';

    # get top level taxon element , should only be one
    foreach my $element ( $root->findnodes('taxon') ) {
        print $element->toString, "\n";

        my $node = {
            parentNodes => [],
            childNodes  => [],
            description => '',
            id          => '',
            label       => '',
        };

        foreach my $attr ( $element->attributes ) {
            # print $attr->name, " : ", $attr->value, "\n";

            # print $attr->serializeContent , "\n" ;

            
            if ( $attr->name eq 'scientificName' ) {
                my ($name)  = $attr->value =~ /([\w\s\-]+) metagenome/;
                $node->{label} = $name || $attr->value ;
              }
            $node->{id} = ( "Taxonomy:" . $attr->value )
              if ( $attr->name eq 'taxId' );
        }

        foreach my $element ( $root->findnodes('//synonym') ) {
          print STDERR $element->toString , "\n" ;
          foreach my $attr ( $element->attributes ) {
            if ( $attr->name eq 'name' ) {
              # remove metagenome string
              my ($name)  = $attr->value =~ /([\w\s]+) metagenome/;
            
              if ($node->{description}){
                $node->{description} = join ";" , ($node->{description} , $name || $attr->value ) ;
              }
              else{
                $node->{description} = $name || $attr->value ;
              }
              
            }
          }
        }

        # Add parent ID if exists ;
        push @{ $node->{parentNodes} }, ( $parent->{id} )
          if ($parent);

        # Add node to node list
        $data->{nodes}->{ $node->{id} } = $node;

        # Get children and add to children list and create nodes for children

        my @children = $root->findnodes('//children/taxon');
        foreach my $child (@children) {

            foreach my $attr ( $child->attributes ) {
                print $attr->name, " : ", $attr->value, "\n";
                if ( $attr->name eq 'taxId' ) {
                    push @{ $node->{childNodes} }, "Taxonomy:" . $attr->value;
                    &createNode( $data, $node, $attr->value );
                }
            }

        }
    }

}


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
    my ( $type, $taxid, $ua ) = @_;

    my $url =
        'http://www.ebi.ac.uk/ena/data/view/Taxon:'
      . $taxid
      . '&display=xml&download=xml&filename='
      . $taxid . '.xml';
    my $response = $ua->get($url);

    unless ( $response->is_success ) {
        print STDERR "Error retrieving data\n";
        print STDERR $response->status_line, "\n";
        exit;
    }

    my $dom = XML::LibXML->load_xml( string => $response->content );
    my $root = $dom->documentElement;

    foreach my $node ( $root->findnodes('//children/taxon') ) {

#print join "\t" , "Found:" , $node->nodeName , ($node->nodeValue || "none") , $node->textContent , ($node->attributes) , "\n" ;

        my @attribs = $node->attributes();

      #print "Value:\t" , $attribs[0]->value , "\t", $attribs[1]->value , "\n" ;
        my $tmp1 = $attribs[0]->value;
        my $tmp2 = $attribs[1]->value;

 # my ($name)  = $attribs[0]->value =~ /scientificName="([\w\s]+) metagenome"/ ;
 # my ($taxid) = $attribs[1]->value =~ /taxId="(\d+)"/ ;
        my ($name)  = $attribs[0]->value =~ /([\w\s]+) metagenome/;
        my ($taxid) = $attribs[1]->value =~ /(\d+)/;
        print TSV join( "\t",
            $type,
            ( $name || $attribs[0]->value || 'error' ),
            $taxid || 'error' ),
          "\n";
    }

}

