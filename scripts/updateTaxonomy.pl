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

# Files to compare - json
my $previous_version  = undef ;
my $new_version       = undef ;

# Options
my $help                      = 0 ;
my $update_taxonomy           = 0 ;
my $debug                     = 0 ;
my $dry_run                   = 0 ;
my $all                       = 0 ;
my $get_taxonomy_from_mgrast  = 0 ;
my $compare_taxonomy          = 0 ;
my $token                     = undef ; # MG-RAST token


# URL to retrieve latest taxonomy from
my $host      = "http://api.metagenomics.anl.gov" ;
my $get_url   = "$host/metadata/ontology?name=metagenome_taxonomy&version=latest" ;
my $shock_url = "http://shock.metagenomics.anl.gov/node/" ;

# Set $update_taxonomy only if you want to force an update, otherwise set to no_update

GetOptions(
     'help'   => \$help,
     'dryRun' => \$dry_run,
     'token=s'=> \$token,
	   'old=s'  => \$previous_version ,
	   'new=s'  => \$new_version,
     'debug'  => \$debug,
     'all'    => \$all,
     'getCurrentTaxonomy' => \$get_taxonomy_from_mgrast , 
     'compareTaxonomy'    => \$compare_taxonomy ,
     'updateTaxonomy'     => \$update_taxonomy , 
     );

if ($help) {
  print "Usage: $0 -dryRun -new <FILE> (-old <FILE> || -getCurrentTaxonomy) -compareTaxonomy -updateTaxonomy -debug -token <TOKEN>\n" ;
  exit;
}
     
if ($all) {
  $get_taxonomy_from_mgrast = 1 ;
  $compare_taxonomy         = 1 ;
}   

# Get token from env
unless($token){
  $token = $ENV{"MGRAST_TOKEN"} ;
}

# initialise user agent
my $ua = LWP::UserAgent->new;
$ua->agent('MG-RAST Update Taxonomy Client 0.1');

# initialize json 
my $json = new JSON ;


# Get current and new version
# compare with previous version
# if different 
# a) update previous, change version number from latest to date
# b) push new to shock and update via api

if ($get_taxonomy_from_mgrast) {
  print STDERR "DEBUG: Retrieving current taxonomy from MG-RAST\n" if ($debug);
  
  if ($previous_version and -f $previous_version) {
    print STDERR "Error: Conflict, taxonomy file provided but also option to retrieve from MG-RAST.\n" ;
    print STDERR "Error: File = $previous_version\n" ;
    print STDERR "Error: URL  = $get_url\n" ;
    exit ;
  }
  else{
    $previous_version = &get_current_list($get_url)
  } 
}

if ($compare_taxonomy) {
  print STDERR "DEBUG: Comparing taxa files\n" if ($debug);
  $update_taxonomy = compareTaxonomyFiles( $previous_version , $new_version );
  print STDERR "DEBUG: update=$update_taxonomy\n" if ($debug) ;
  
}

if ($update_taxonomy){
  
  my $time = gmtime() ;
  $time =~ s/(\d\d\d\d)$/UTC $1/ ; 
  
  print STDERR "DEBUG: Updating taxa ($time)\n" if ($debug);
   
  my $delete_url = "$host/metadata/ontology?name=metagenome_taxonomy&version=latest";
  my $update_url = "$host/metadata/ontology";
  
 
  
  
  # Read from file
  # 1. Delete MG-RAST Version
  # 2. Create new MG-RAST Version
  # 3. Add to Shock archive with current download date as version number
  

  # Read from file and transform into input for API  
  open(NEW , $new_version) or die "Can't open $new_version for reading.\n" ;

  my $tmp = '' ;
  while (my $line = <NEW>){
    $tmp .= $line ;
  }
  my $new    = $json->decode($tmp) ; 
  my $nodes  = $new->{nodes} ;
  
  # Create nodes file for API upload
  if (keys %$nodes) {
    
    open(NODES , ">nodes.json") or die "Can't open file nodes.json for writing.\n" ;
    print NODES $json->encode($nodes) ;
    close NODES ;
  }
  else{
    print STDERR "ERROR: Somthing wrong, no nodes.\n" ;
    print STDERR "ERROR: " , Dumper $nodes ;
    print STDERR "DEBUG: " , Dumper $new if ($debug) ;
    exit;
  }
  
  my $update_mgrast = 1 ;
  if ($update_mgrast) {
    # 1. Delete MG-RAST Version
    print STDERR "DEBUG: Deleting version in MG-RAST\n" if ($debug) ;
    print STDERR "DEBUG: curl -s -X DELETE -H \"authorization: mgrast $token\" \"$delete_url\"\n" if ($debug) ;
    my $message = `curl -s -X DELETE -H "authorization: mgrast $token" "$delete_url"` unless ($dry_run);
    
    if ($message){
      my $error = $json->decode($message) ;
      print STDERR "ERROR: " . $error->{ERROR} . "\n" if $error->{ERROR} ;
    }

    # 2. Create new MG-RAST Version
    print STDERR "DEBUG: Updating version in MG-RAST\n" if ($debug) ;
 
    my $rootNode = $new->{rootNode} ;
    print STDERR "DEBUG: curl -s -X POST -F \"upload=\@nodes.json\" -F \"name=metagenome_taxonomy\" -F \"root=$rootNode\" -F \"version=latest\" -H \"authorization: mgrast $token\" \"$update_url\"\n" if ($debug) ;
 
    
    
    my $response = `curl -s -X POST -F "upload=\@nodes.json" -F "name=metagenome_taxonomy" -F "root=$rootNode" -F "version=latest" -H "authorization: mgrast $token" "$update_url" ` unless ($dry_run);
    
    if ($response){
      my $message = $json->decode($response) ;
      print STDERR "ERROR: " . $message->{ERROR} . "\n" if $message->{ERROR} ;
      
      if ($message->{status} eq "200") {
        print "Taxonomy file archived, node: " . $message->{data}->{id} . "\n" ;
      }
      else{
        print $message , "\n";
      }
    }
  }
  
  my $add_to_shock = 1 ;
  if ($add_to_shock) {
    # 
    
    my $shock_attr = {
        "nr_nodes"    => scalar keys %{$new->{nodes}} ,  # get number of nodes from new
        "version"     => $new->{version},
        "download"    => $new->{download},
        "name"        => "EBI Taxonomy (subtree)",
        "type"        => "cv",    # "taxonomy"
        "data_type"   => 'taxonomy' ,
        "file_type"   => 'json' ,
        "description" => 'Metagenome subtree of the taxonomy'
    };
    
    print Dumper $shock_attr ;
    
    # with attributes file
    # curl -X POST -F "attributes=@<path_to_json_file>" http://<host>[:<port>]/node
    # with file, using multipart form
    # curl -X POST -F "upload=@<path_to_data_file>" http://<host>[:<port>]/node
    
    my $attr = $json->encode($shock_attr) ;
    
    print qq~ 
curl -X POST -H "authorization: mgrast $token" \\
  -F "upload=\@$new_version" \\
  -F 'attributes_str=$attr' \\
  "$shock_url"     
~ ; 
    
    my $response = `curl -X POST -H "authorization: mgrast $token" \\
      -F "upload=\@$new_version" \\
      -F 'attributes_str=$attr' \\
      "$shock_url"` unless ($dry_run);
  
    if ($response){
      my $message = $json->decode($response) ;
      print STDERR "ERROR: " . $message->{ERROR} . "\n" if $message->{ERROR} ;
      if ($message->{status} eq "200") {
        print "Taxonomy file archived, node: " . $message->{data}->{id} . "\n" ;
      }
    }
    
  }
  
  
}





sub get_current_list {
  my ($url , $file) = @_ ;
  
  # Set file name if not provided
  $file = "taxonomy.current.json" unless ($file) ;
  my $error = `curl -s -X GET "$url" > $file` ;
  
  print STDERR "Error: $error \n" if ($error);
  
  return $file ;
}

sub compareTaxonomyFiles {
  my ($current_version , $new_version) = @_ ;
  
  # Compare the two structures, set $different to true if not identical
  my $different = 0 ;
  
  unless(-f $current_version and -f $new_version) {
    print STDERR "Error: filename provided but ot valid file(s) ($current_version and $new_version)\n" ;
  }
  
  open(OLD , $current_version) or die "Can't open $current_version for reading.\n" ;
  open(NEW , $new_version) or die "Can't open $new_version for reading.\n" ;

  # READ old version
  my $tmp = '' ;
  while (my $line = <OLD>){
    $tmp .= $line ;
  }
  my $old = $json->decode($tmp) ;

  # READ new version
  $tmp = '' ;
  while (my $line = <NEW>){
    $tmp .= $line ;
  }
  my $new = $json->decode($tmp) ;




  if (scalar (keys %{$old->{nodes}}) == scalar (keys %{$new->{nodes}})){
  
    foreach my $old_id (keys %{$old->{nodes}}){
    
      if ($new->{nodes}->{$old_id}){
        my $old_node = $old->{nodes}->{$old_id} ;
        my $new_node = $new->{nodes}->{$old_id} ;
      
        if ( not ( $old_node->{label} eq $new_node->{label} ) ){
          $different = 1;
           print STDERR "Different label for $old_id.\n" ;
        }
      
      }
      else{
        $different = 1;
        print STDERR "Can't find $old_id in new list.\n" ;
      }
    
    }
   
  
  }
  else{
    print STDERR "Different lists, not same number of nodes.\n" ;
    $different = 1 ;
  }

  
  return $different ;
}

