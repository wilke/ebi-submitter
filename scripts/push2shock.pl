#!/usr/bin/env perl
use strict;
use warnings;

use Data::Dumper ;
use LWP::UserAgent;
use JSON;
use XML::Simple ;
use Getopt::Long;
use Net::FTP;


my $mgmID   = "mgm000" ;
my $pattern = { 
  scrubbed  => "$mgmID.scrubbed.fast*" ,
  log       => "$mgmID.scrubbed.log" ,
  adapter   => "$mgmID.adapter.fa" ,
} ;




# Global settings
my $dryrun  = 0 ;
my $verbose = 0 ;
my $debug   = 0 ;
my $force   = 0 ; # force push to shock

my $shockHost   = "http://localhost:7445" || "http://shock.metagenomics.anl.gov" ;
my $mgrastHost  = "http://api.metagenomics.anl.gov" ;
my $token       =  $ENV{SHOCK_TOKEN} || undef ;
my $stage_id    = "060" ;
my $stage_name  = "adapter removal" ;
my $pipeline_version = "0.9"            || $ENV{PIPELINE_VERSION};
my $pipeline_name    = "EBI Submitter"  || $ENV{PIPELINE_NAME} ;


my $fileID = {
  scrubbed => {
    id => $stage_id . ".1" ,
    pattern => 'mgm\d+.+\.scrubbed.fast[a|q]' ,
    data_type => "sequence" ,
    file_format => undef ,
  },
  adapter => {
    id => $stage_id . ".2" ,
    pattern => 'mgm\d+.+\.adapter.fa' ,
    data_type => "sequence" ,
    file_format => "fasta" ,
  },
  log => {
    id => $stage_id . ".3" ,
    pattern => 'mgm\d+.+\.scrubbed.log' ,
    data_type => "statistics" ,
    file_format => "txt" ,
  },
  receipt => {
    id => undef ,
    pattern => 'receipt.xml',
    data_type => 'submission' ,
    file_format => "xml" ,
  },
};

# Files to push
my $files = { 
  scrubbed => undef , 
  adapter  => undef ,
  log      => undef ,
};

# EBI submission receipt;
my $submissionReceipt = undef ; 

# Input 
my $data_dir = undef ; # push files from data dir with specified pattern




GetOptions(
  'file=s'        => \$pattern , 
  'verbose'       => \$verbose ,
  'debug'         => \$debug,
  'scrubbed=s'    => \$files->{scrubbed} ,
  'adapter=s'     => \$files->{adapter} ,
  'log=s'         => \$files->{log} ,
  'receipt=s'     => \$submissionReceipt ,
  'dir=s'         => \$data_dir , 
  'dryrun'        => \$dryrun ,
  'shock=s'       => \$shockHost ,
  'token=s'       => \$token ,
  'stage_id=s'    => \$stage_id,
  'stage_name=s'  => \$stage_name,
  'force'         => \$force,
);  
 
 
#################### 
# Check 
###################

my $success = 1 ;

# input files
for my $type  (keys %$files){
  unless(defined $files->{$type} and -f $files->{$type}){
     print STDERR "No valid file for $type: " . $files->{$type} . "\n" ;
     $success = 0 ;
  } 
}

# token
unless($token){
  print STDERR "Missing token, can't submit to shock.\nPlease provide through command line or set \$SHOCK_TOKEN\n" ;
  # test if shock allows anonymous write
  $success = 0 unless ($dryrun) ;
}

my $auth = '' ;
if ($token){
  $auth = "Authorization: mgrast $token" ;
}


unless ($success){
  print STDERR "Found errors, aborting!\n" ;
  exit;
}


#####################
# json handle
####################
my $json = new JSON;

####################
# Initiate User agent
###################

my $ua = LWP::UserAgent->new;
$ua->agent('EBI/Shock 0.1');
$ua->default_header( Authorization => "mgrast $token" );

####################
# Create attributes and upload to Shock
###################


for my $key (keys %$files){
  if (-f $files->{$key}) {
    # Create attributes file
    my ($attributes) = &create_attributes($files->{$key} , $key) ;
    # Upload new file to shock or create a copy node
    &push2shock($files->{$key} , $attributes) ;
  }
}

if (-f $submissionReceipt){
  # 1. Check if xml
  unless( $submissionReceipt =~ /.xml$/){
    print STDERR "Not an XML file, missing xml suffix.\n";
    exit;
  }
  # 2. Parse xml
  my $attributes = &parse_receipt($submissionReceipt);
  unless( $attributes and ref $attributes){
    print STDERR "Can't parse $submissionReceipt and create attributes.\n";
    exit;
  }
  # 3. Upload to Shock
  &push2shock($submissionReceipt , $attributes) ;
}

#END MAIN###############
 
sub find_files_with_pattern{
  my ($mgmID) = @_ ;    
}

sub get_md5{
  my ($file)  = @_ ;
  
  my $md5bin =  `which md5sum `;
  chomp $md5bin ;
  print "TEST:\n" , $md5bin , "END\n";
  
  # which md5 script, linux versus mac
  
  unless($md5bin){
    $md5bin =  `which md5`;
    chomp $md5bin ;
    unless($md5bin){
      print STDERR "Can't compute md5 sum. Can't find md5 tool.\n";
      exit;
    }
    else{
      $md5bin .= " -r" ;
    }
  }
  
  my $result     = `$md5bin $file` ;  
  my ($md5 , $f) = split " " , $result ;

  unless($md5){
    print STDERR "Can't compute md5 for $file\n" ;
    exit;
  }
  unless($f eq $file){
    print STDERR "Something wrong, computed md5 for wrong file:\n($file\t$f)\n";
    exit;
  }  
  
  print STDERR "MD5 for local files:\t" , $result , "\n" if ($debug);
  return $md5 ;
} 

sub get_seq_count{
  my ($fasta) = @_ ;
  
  my $var = `fgrep ">" $fasta | wc -l` ;
  my ($count) = $var =~ /\s*(\d+)/ ;
  return $count ;
} 

sub get_stats{  
  # call seq stats script ?
}  

  
sub get_filename{
  my ($file) = @_ ;
  
  my ($basename)  = $file =~ /(mgm[^\/]+)$/ ;  
  my ($id)        = $basename =~ /^(mgm\d+\.\d+)/;
  
  unless($id){
    print STDERR "Error: Can not find metagenome ID.\n" ;
    print STDERR "Error: $basename\t$file\n" ;
    exit;
  }
  
  return $id ;
}

sub get_mgid_basename{
  my ($file) = @_ ;
  
  my ($basename)  = $file =~ /(mgm[^\/]+)$/ ;  
  my ($id)        = $basename =~ /^(mgm\d+\.\d+)/;
  
  unless($id){
    print STDERR "Error: Can not find metagenome ID.\n" ;
    print STDERR "Error: $basename\t$file\n" ;
    exit;
  }
  
  return ($id , $basename);
}  
  
sub get_metagenome{
  my ($mgid) = @_ ;
  
  my $response = $ua->get( "$mgrastHost/metagenome/$mgid?verbosity=mixs");
  
  unless($response->is_success){
    print STDERR "Error retrieving data for $mgid\n";
    print STDERR $response->status_line , "\n" ;
    my $error = 1 ;
    eval{
      print STDERR $response->content , "\n" ;
      my $tmp = $json->decode($response->content) ;
      $error = $tmp->{ERROR} if $tmp->{ERROR} ;
    };
    return ( undef , $error) ;
  }
  
  my $json = new JSON;
  my $data = undef;
  
  # error handling if not json
  eval{
    $data = $json->decode($response->content)
  };
  
  if($@){
    print STDERR "Error: $@\n";
    exit;
  }
  
  if (defined $data->{ERROR} and $data->{ERROR}){
    print STDERR "Error: Can't retrieve $mgid , " . $data->{ERROR} . "\n" ;
    exit;
  }
    
  return $data ;
}  
  

# Check if node with given attributes exists 
sub query_node{
  my ($attributes) = @_ ;

  print STDERR "Checking if file with attributes already in Shock\n" if ($verbose) ;
  my $url = "$shockHost/node?query";
  
  my $query = join "&" , ("type=metagenome") , 
              "file_name=" . $attributes->{file_name} , 
              "file_md5="  . $attributes->{file_md5} ;
  
  my $response = $ua->get( $url ."&" . $query );
  
  unless($response->is_success){
    print STDERR "Error retrieving data\n";
    print STDERR $response->status_line , "\n" . $url ."?" . $query . "\n" ;
    my $error = 1 ;
    eval{
      print STDERR $response->content , "\n" ;
      my $tmp = $json->decode($response->content) ;
      $error = $tmp->{ERROR} if $tmp->{ERROR} ;
    };
    return ( undef , $error) ;
  }
  
  my $json = new JSON;
  my $data = undef;
  
  # error handling if not json
  eval{
    $data = $json->decode($response->content)
  };
  
  if($@){
    print STDERR "Error: $@\n";
    exit;
  }
  
  if (defined $data->{ERROR} and $data->{ERROR}){
    print STDERR "Error: Can't retrieve: , " . $data->{ERROR} . "\n" ;
    exit;
  }
  
  if ($debug){
    print STDERR "Query:\t" , $url ."?" . $query  , "\n" ;
    print STDERR "Results:\n" , Dumper $data ;
  }
  
  my $exists = 0 ;
  $exists = 1 if (scalar @{$data->{data}}) ;
    
  return ($exists , $data) ;
}  

sub parse_receipt{
  my ($submissionReceipt);

  return undef ;
}
# Create attributes for pipeline stage  
sub create_attributes{
  my ($file , $type) = @_ ;
   
  my ($mgid , $basename) = &get_mgid_basename($file);
  my ($suffix) = $basename =~ /(\w+\.\w+)$/ ;
  # my $stage_id    = "060" ; Global parameter
  
  
  print STDERR join "\t" , $file , $type , "\n" if ($debug); 
  
  my $file_format = $fileID->{$type}->{file_format} || undef  ;
  
  unless($file_format){
    ($file_format) = $basename =~ /\.(\w+)$/ ; 
  }
  
  
  # retrieve metagenome name and project info from metagenome resource
  my $mg = &get_metagenome($mgid) ;
  
  my $attributes = {
    file_md5	=>  &get_md5($file) ,
    created => undef ,
    data_type	=> $fileID->{$type}->{data_type} ,
    file_format	=> $file_format ,
    id	=> $mgid ,
    job_id => $mg->{job_id} ,
    name => $mg->{name} ,
    pipeline_version => $pipeline_version ,
    pipeline_name    => $pipeline_name ,
    project_id => $mg->{project_id} ,
    project_name => $mg->{project_name} ,
    seq_format => undef ,
    stage_id	=> $stage_id ,
    stage_name	=> "adapter removal" ,
    file_id	=> $fileID->{$type}->{id} ,
    file_name	=> join ("." , $mgid , $stage_id , $suffix) , 
    type => "metagenome" ,
    status => $mg->{status} ,
  };
  
  # Get stats if sequences 
  if ($fileID->{$type}->{data_type} eq "sequence"){
    $attributes->{statistics} = {
      #### RUN SEQUENCE STATS #########
      sequence_count	=> &get_seq_count($file) ,
    }
  }
 
  return $attributes ;
}

sub push2shock{
  my ($file , $attributes) = @_ ;
  

  print STDERR "Starting processing $file\n" if ($verbose) ;
  
  unless(-f $file){
    print STDERR "Not uploading to shock, no file $file\n";
    return 
  }
 
  # Check if node with attributes already exists
  my ($found , $data) = &query_node($attributes) ;
    
    
  # Upload
  if(not $found or $force){  
    
    # Write attributes to file
    my $attributesFile = "$file.attributes.json" ;  
    open(JSONFILE , ">$attributesFile") or die "Can't open file $attributesFile for writing!\n" ;
    print JSONFILE $json->encode($attributes) ;
    close JSONFILE ;
    
    # POST to Shock
    my $fname = $attributes->{file_name} ;
    my $call = "curl -X POST -H \"$auth\" -F \"attributes=\@$attributesFile\" -F \"upload=\@$file\" -F \"file_name=$fname\" $shockHost/node";
    print STDERR join "\t" , "Uploading:" ,   ($file || 'missing') , "\n$call\n" if ($verbose); 
    my $receipt = `$call` unless ($dryrun);
    
    # Parse receipt
    my $rcj = $json->decode($receipt);
  
    # Check if uploded file is identical
    my $upload = "ok";
    unless ($rcj->{data}->{file}->{checksum}->{md5} eq $attributes->{file_md5}){
      $upload = "error" ;
    }
    open(FILE , ">$file.shock.receipt.json") or die ("Can't open file receipt.json for writing.");
    print FILE join "\t" , "Upload:$upload" ,  "Node:" . $rcj->{data}->{id} , "File:$file\n" ; 
    print STDERR join "\t" , "Upload:$upload" ,  "Node:" . $rcj->{data}->{id} , "File:$file\n\n" if ($verbose); 
    print STDERR Dumper $receipt if ($debug);
    close FILE ;
  }
  else{
    # Verbose output
    my @nodes ;
    foreach my $node (@{$data->{data}}){
      push @nodes , $node->{id} ;
    }
    if ($verbose){
      print STDERR "Skipping upload, file already in Shock. Write update function if needed.\n";
      print STDERR "Nodes:\t" , join(" ; " , @nodes) , "\n\n" ; 
    }
  }
  
}