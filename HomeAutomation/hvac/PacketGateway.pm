package hvac::PacketGateway;
use strict;

sub new {
    my $class = shift;
    my $self  = { _vars => shift, };
    bless $self, $class;
    return $self;
}

our $DEBUG = 0;

sub process_request {
    my $self = shift;
    my $c    = shift;
    my $r    = shift;
    my $msg;

    #We take arguments. Either as HTTP POST or GET. Find them...
    my $buffer;
    my @pairs;
    my $pair;
    my $name;
    my $value;
    my %FORM;

    # Read in text
    my $method = $r->method;
    $method =~ tr/a-z/A-Z/;
    if ( $method eq "POST" ) {
        $buffer = $r->content;
    }
    elsif ( $method eq "GET" ) {
        $buffer = $r->uri->query;
    }
    else {
        $c->send_error(HTTP::Status::HTTP_FORBIDDEN);
        return;
    }

    # Split information into name/value pairs
    if ( !defined($buffer) ) { $buffer = ""; }
    @pairs = split( /&/, $buffer );
    foreach $pair (@pairs) {
        ( $name, $value ) = split( /=/, $pair );
        $value =~ tr/+/ /;
        $value =~ s/%(..)/pack("C", hex($1))/eg;
        $FORM{$name} = $value;
    }

    #use WirelessGateway
    my $cmdBase =
        $ENV{HTTPD_LOCAL_ROOT}
      . "/../hvac/procWirelessGateway "
      . $self->{_vars}->{FURNACE_GATEWAY_DEVICE} . " ";
    my $cmd;
    my $nodeNumber = "";
    if ( defined( $FORM{nodenumber} ) ) {
        $nodeNumber = $FORM{nodenumber};
        my $textToSend = $FORM{texttosend};
        if ( "" ne $nodeNumber && "" ne $textToSend ) {
            if ( defined( $FORM{sendmessage} ) ) {
                $cmd =
                  $cmdBase . "SEND " . $nodeNumber . " \"" . $textToSend . "\"";
            }
            elsif ( defined( $FORM{queuemessage} ) ) {
                $cmd =
                    $cmdBase
                  . "FORWARD "
                  . $nodeNumber . " \""
                  . $textToSend . "\"";
            }
        }
    }
    if ( defined( $FORM{getmessages} ) ) {
        $cmd = $cmdBase . "GETALL";
    }
    my @response;
    if ( defined($cmd) ) {
        my ( $my_reader, $my_writer );
        my $pid = IPC::Open2::open2( $my_reader, $my_writer, $cmd );
        $my_writer->autoflush(1);
        $my_reader->autoflush(1);
        close $my_writer;
        while ( my $line = <$my_reader> ) {
            push( @response, $line );
        }
        close $my_reader;
    }

    # required http header cuz we're CGI
    $msg = <<FirstSectionDone;
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Packet Gateway</title>
</head>
<body>
FirstSectionDone

    if ($DEBUG) {
        $msg .= "FORM: <br/> \n";
        while ( my ( $key, $value ) = each(%FORM) ) {
            $msg .= "$key => $value<br/>\n";
        }
    }

    $cmd = defined($cmd) ? "<code>" . $cmd . "</code><br/>" : "";

    my $nodeValue = "";
    $nodeValue = "value='" . $nodeNumber . "'" if ( "" ne $nodeNumber );

    $msg .= <<Form_print_done1;
$cmd
<form action="" method="POST">
<table border="1">
<tr><th>Node</th><th colspan='3' align='center'>Text</th></tr>
<tr>
<td align='center'>
<input type='number' id='nodenumber' name='nodenumber' min='1' max='255' $nodeValue></input>
</td>
<td colspan='3' align='center'>
<input type='text' size='60' id='texttosend' name='texttosend'></input>
</td>
</tr>
<tr>
<td></td>
<td><input type='submit' name='sendmessage' id='sendmessage' value='Send'></input></td>
<td><input type='submit' name='queuemessage' id='queuemessage' value='Queue'></input></td>
<td><input type='submit' name='getmessages' id='getmessages' value='List'></input></td>
</tr>
</table>
</form>
Form_print_done1

    foreach my $line (@response) {
        $msg .= "<code>" . $line . "</code><br/>" . "\n";
    }

    $msg .= <<Form_print_done2;
</body>
</html>
Form_print_done2

    my $response = HTTP::Response->new(HTTP::Status::HTTP_OK);
    $response->header( "Content-type" => "text/html" );
    $response->content($msg);
    $c->send_response($response);
}

1;

