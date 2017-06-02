package Submitter ;

sub get_json_from_url {
  my ($user_agent,$url, $resource, $metagenome_id, $options) = @_;
  my $response = $ua->get( join "/" , $url, $resource , $metagenome_id , $options);
  
  unless($response->is_success){
    print STDERR "Error retrieving data for $metagenome_id\n";
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
  return $data;
}