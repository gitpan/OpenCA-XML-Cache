## OpenCA::XML::Cache
##
## Copyright (C) 2000-2003 Michael Bell (michael.bell@web.de)
##
## GNU Public License Version 2
##
## see file LICENSE or contact
##   Free Software Foundation, Inc.
##   675 Mass Ave, Cambridge, MA 02139, USA
##

use strict;

package OpenCA::XML::Cache;

use XML::Twig;
use Socket;
## use Carp;

use POSIX;
use English;
## use IPC::SysV;
## use IPC::SysV qw (IPC_RMID IPC_CREAT);

## the other use directions depends from the used databases
## $Revision: 0.1.1.2 

($OpenCA::XML::Cache::VERSION = '$Revision: 1.3 $' )=~ s/(?:^.*: (\d+))|(?:\s+\$$)/defined $1?"0\.9":""/eg; 

$OpenCA::XML::Cache::ERROR = {
                       SETUID_FAILED       => -101,
                       SETGID_FAILED       => -102,
                       MKFIFO_FAILED       => -103,
                       OPEN_FIFO_FAILED    => -104,
                       OPEN_PIDFILE_FAILED => -105,
                       FORK_FAILED         => -108,
                       MSGGET_FAILED       => -109,
                       MSGRCV_FAILED       => -110,
                       OPEN_SOCKET_FAILED  => -111,
                      };

## Hit it in your phone if don't know what does this key mean ;-D
$OpenCA::XML::Cache::SOCKET_FILE = "/tmp/openca_xml_cache";

my $params = {
              SOCKET_FILE   => $OpenCA::XML::Cache::SOCKET_FILE,
              IPC_USER      => undef,
              IPC_GROUP     => undef,
              IPC_UID       => undef,
              IPC_GID       => undef,
              DEBUG         => 0,
              DEBUG_CT      => 0,
              USAGE_COUNTER => 0
	     };

## functions
##
## new
## _init
## _doLog
## _debug
##
## startDaemon
## stopDaemon
## getMessage
## getData
##
## getTwig 

#######################################
##          General functions        ##
#######################################

sub new { 
  
  # no idea what this should do
  
  my $that  = shift;
  my $class = ref($that) || $that;
  
  ## my $self  = $params;
  my $self;
  my $help;
  foreach $help (keys %{$params}) {
    $self->{$help} = $params->{$help};
  }
   
  bless $self, $class;

  # ok here I start ;-)

  $self->_init (@_);

  return $self;
}

sub _init {
  my $self = shift;
  my $keys = { @_ };

  $self->{DEBUG} = $keys->{DEBUG} if ($keys->{DEBUG});

  $self->debug ("_init: init of OpenCA::XML::Cache");

  ## this class can be created for several reasons
  ## 1. signing
  ## 2. backup
  ## 3. backup-verification
  ## 4. database-recovery
  ## 5. database-recovery from backup

  ## actually only signing is supported

  ## general configuration

  $self->debug ("_init: general parts ...");

  ## checking for given pipename
  $self->{PIDFILE}       = $keys->{PIDFILE}       if ($keys->{PIDFILE});
  $self->{LOGFILE}       = $keys->{LOGFILE}       if ($keys->{LOGFILE});
  $self->{SOCKETFILE}    = $keys->{SOCKETFILE}    if ($keys->{SOCKETFILE});
  $self->{IPC_USER}      = $keys->{IPC_USER}      if ($keys->{IPC_USER});
  $self->{IPC_GROUP}     = $keys->{IPC_GROUP}     if ($keys->{IPC_GROUP});
  $self->{FILENAME}      = $keys->{FILENAME}      if ($keys->{FILENAME});
  $self->{XPATH}         = $keys->{XPATH}         if ($keys->{XPATH});
  $self->{COUNTER}       = $keys->{COUNTER}       if ($keys->{COUNTER});

  ## configure uid
  if ($self->{IPC_USER}) {
    my @passwd = getpwnam ($self->{IPC_USER});
    if (@passwd) {
      $self->{IPC_UID} = $passwd[2];
    }
  } else {
    $self->debug ("_init: IPC_UID not given so $<");
    $self->{IPC_UID} = $<                 if (not $self->{IPC_UID});
  }

  ## configure group
  if ($self->{IPC_GROUP}) {
    my @passwd = getgrnam ($self->{IPC_GROUP});
    if (@passwd) {
      $self->{IPC_GID} = $passwd[2];
    }
  } else {
    $self->debug ("_init: IPC_GID not given so ".getgid."\n");
    $self->{IPC_GID} = getgid                 if (not $self->{IPC_GID}); 
  }

  $self->debug ("_init: init of OpenCA::XML::Cache completed");

  return 1;
}

sub doLog {
  my $self = shift;

  if (not open (LOGFILE, ">>".$self->{LOGFILE})) {
    print STDOUT "WARNING: cannot write logfile \"".$self->{LOGFILE}."\"\n";
    print STDOUT "MESSAGE: ".$_[0]."\n";
  } else {
    if ($self->{DEBUG}) {
      print STDOUT "LOGMESSAGE: ".$_[0]."\n";
    }
    print LOGFILE "\n".gmtime()." message:\n";
    print LOGFILE $_[0];
    close LOGFILE;
  }
}

sub debug {
  my $self = shift;

  if ($self->{DEBUG}) {

    if (not $self->{DEBUG_CT})
    {
        $self->{DEBUG_CT} = 1;
        print "content-type: text/html\n\n";
    }

    my $help = $_[0];
    $help =~ s/\n/<br>\n/g;
    print STDERR ("OpenCA::XML::Cache->".$help."<br>\n");
    print ("OpenCA::XML::Cache->".$help."<br>\n");

    if ($_[1])
    {
      print "    FILENAME      ".$self->{FILENAME}."\n";
      print "    XPATH         ".$self->{XPATH}."\n";
      print "    COUNTER       ".$self->{COUNTER}."\n";
      print "    SOCKET_FILE   ".$self->{SOCKET_FILE}."\n";
      print "    IPC_USER      ".$self->{IPC_USER}."\n";
      print "    IPC_GROUP     ".$self->{IPC_GROUP}."\n";
      print "    IPC_UID       ".$self->{IPC_UID}."\n";
      print "    IPC_GID       ".$self->{IPC_GID}."\n";
      print "    PIDFILE       ".$self->{PIDFILE}."\n";
      print "    LOGFILE       ".$self->{LOGFILE}."\n";
    }
  }
  return;
}

###################################
##        daemon functions       ##
###################################

sub startDaemon {

  my $self = shift;
  my $keys = { @_ };
 
  $self->_init (@_);

  $self->debug ("startDaemon");

  ## check for a running daemon

  my $pid = $self->getPID();
  if ($pid)
  {
      ## return if daemon already exists
      return 1 if (getpgrp ($pid) and getpgrp ($pid) > 0);
  }

  ## check for actual user and group
  ## change to predefined user and group if necessary

  if ($UID != $self->{IPC_UID}) {
    ## try to set correct uid
    if (POSIX::setuid ($self->{IPC_UID}) < 0) {
      return $OpenCA::XML::Cache::ERROR->{SETUID_FAILED};
    }
  }
  if ($GID != $self->{IPC_GID}) {
    ## try to set correct uid
    if (POSIX::setgid ($self->{IPC_GID}) < 0) {
      return $OpenCA::XML::Cache::ERROR->{SETGID_FAILED};
    }
  }
 
  $self->debug ("startDaemon: UID and PID ok");

  ## initialize socket
  my $socket = $self->{SOCKET_FILE};
  my $uaddr = sockaddr_un($socket);
  umask (0177);
  $self->debug ("startDaemon: uaddr: $uaddr");
  $self->debug ("startDaemon: maxconn: ".SOMAXCONN);

  socket(Server,PF_UNIX,SOCK_STREAM,0) || return undef;
  unlink($socket);
  bind  (Server, $uaddr)               || return undef;
  listen(Server,SOMAXCONN)             || return undef;

  $self->debug ("startDaemon: socket initialized");

  ## fork away for real operation
  my $pid;
  if ($pid = fork ()) {
    
    ## parent finish

    ## preparations to kill the daemon
    $self->debug ("startDaemon: try to open PIDFILE ...");
    if (not open (PIDFILE, ">".$self->{PIDFILE})) {
      my $warning = "WARNING: cannot write pidfile \"".$self->{PIDFILE}."\"\n".
                    "         sub stopSigningDaemon doesn't work!\n";
      print STDOUT $warning;
      $self->doLog ($warning);
    } else {
      $self->debug ("startDaemon: PID: ".$pid); 
      print PIDFILE sprintf ("%d", $pid);
      close PIDFILE;
    }

    ## print to LOGFILE the startup
    $self->doLog ("startSigningDaemon successfull at ".
           gmtime ()." PID: ".sprintf ("%d", $pid)."\n");
    
    ## all ok
    return 1;
    
  } elsif (defined $pid) {
    
    ## undock from parent process
    setpgrp (0, 0);
    POSIX::setsid();

  IPCLOOP: while (1) {

      $self->debug ("IPCLOOP: wait for clients");
      accept (Client, Server) || next;

      ## we cannot fork again because perl create
      ## completely independent processes

      $self->debug ("IPCLOOP: accepted connection from client");

      ## load message
      my $load = "";
      my $line;
      while (defined ($line = <Client>))
      {
          $load .= $line;
          last if ($load =~ /\n\n$/s);
          $self->debug ("IPCLOOP: message until now: $load");
      }
      shutdown (Client, 0);
      $self->debug ("IPCLOOP: message received");

      ## parse message
      my ($filename, $xpath, $counter) = $self->parseMessage ($load);

      ## get the answer
      my $answer = $self->getXML ($filename, $xpath, $counter);
      $self->debug ("IPCLOOP: answer: $answer");
 
      ## send the answer
      $self->debug ("IPCLOOP: write answer to socket");
      send (Client, $answer, 0);
      shutdown (Client, 1);

      ## automatic next IPCLOOP
      $self->debug ("IPCLOOP: request completed");
      
    } ## end of while (1) loop
  } else {
    $self->debug ("startDaemon: daemon cannot fork so startup failed");
    ## print to LOGFILE the startup

    $self->doLog ("startDaemon failed at ".
           gmtime ()." PID: ".sprintf ("%d", $pid)."\n");
    
    return $OpenCA::XML::Cache::ERROR->{FORK_FAILED};
  }
}

sub parseMessage {
  my $self = shift;
  my $message = $_[0];
  my $help = "1";

  $self->debug ("IPCLOOP: received message: $message");

  ## 1. read the filename
  my $filename = $message;
  $filename =~ s/\n.*$//s;
  $message =~ s/^[^\n]*\n//s;
  $self->debug ("IPCLOOP: xml-file: $filename");

  ## read the xpaths and counters
  my @xpath = ();
  my @counter = ();
  my $i = 0;
  while ($message and $message !~ /^\n/)
  {
    ## read the xpath
    $xpath[$i] = $message;
    $xpath[$i] =~ s/\n.*$//s;
    $message =~ s/^[^\n]*\n//s;
    $self->debug ("IPCLOOP: xpath: $xpath[$i]");

    ## read the counter
    $counter[$i] = $message;
    $counter[$i] =~ s/\n.*$//s;
    $message =~ s/^[^\n]*\n//s;
    $self->debug ("IPCLOOP: counter: $counter[$i]");

    $i++;
  }

  return ($filename, \@xpath, \@counter);
}

sub getXML
{
    my $self = shift;
    my $filename = $_[0];
    my $xpath    = $_[1];
    my $counter  = $_[2];
    my $twig;

    ## use first level cache
    my $result = $self->getCached (
                     FILENAME => $filename,
                     XPATH    => $xpath,
                     COUNTER  => $counter);
    return $result if (defined $result);

    ## create Twig object
    if (not $self->{CACHE} or not $self->{CACHE}->{$filename})
    {
        $self->{CACHE}->{$filename} = new XML::Twig;
        return undef if (not $self->{CACHE}->{$filename});
        return undef if (not $self->{CACHE}->{$filename}->safe_parsefile($filename));
    }

    ## use second level cache
    $twig = $self->{CACHE}->{$filename};

    my $ent = $twig;
    $counter = [ reverse @{$counter} ];
    foreach my $xp (@{$xpath})
    {
        my @path = $ent->get_xpath ($xp);
        if (not @path)
        {
            $ent = undef;
            last;
        }
        if ($counter->[scalar @{$counter}-1] < 0)
        {
            ## return the number of elements
            return scalar @path;
        }
        $ent = $path[pop @{$counter}];
    }
    return undef if (not $ent);

    $self->updateCache (
        FILENAME => $filename,
        XPATH    => $xpath,
        COUNTER  => $_[2],
        VALUE    => $ent->field);

    return $ent->field;
}

sub updateCache
{
    my $self = shift;
    my $keys = { @_ };

    my $filename = $keys->{FILENAME};
    my $counter  = $keys->{COUNTER};
    my $xpath    = $keys->{XPATH};
    my $value    = $keys->{VALUE};

    ## fix counter array for cache
    $counter->[scalar @{$counter}-1] = -1
        if ($counter->[scalar @{$counter}-1] < 0);

    ## build cache string
    my $string = $self->getCacheString (XPATH => $xpath, COUNTER => $counter);

    ## store value
    $self->{XPATH_CACHE}->{$filename}->{$string} = $value;

    return 1;
}

sub getCached
{
    my $self = shift;
    my $keys = { @_ };

    my $filename = $keys->{FILENAME};
    my $counter  = $keys->{COUNTER};
    my $xpath    = $keys->{XPATH};

    ## fix counter array for cache
    $counter->[scalar @{$counter}-1] = -1
        if ($counter->[scalar @{$counter}-1] < 0);

    return undef if (not exists $self->{XPATH_CACHE});
    return undef if (not exists $self->{XPATH_CACHE}->{$filename});

    ## build cache string
    my $string = $self->getCacheString (XPATH => $xpath, COUNTER => $counter);

    return undef if (not exists $self->{XPATH_CACHE}->{$filename}->{$string});
    return $self->{XPATH_CACHE}->{$filename}->{$string};
}

sub getCacheString
{
    my $self = shift;
    my $keys = { @_ };
    my $counter  = [ reverse @{$keys->{COUNTER}} ];
    my $xpath    = $keys->{XPATH};
    my $string   = "";

    foreach my $xp (@{$xpath})
    {
        $string .= "<".$xp.">";
        $string .= pop @{$counter};
    }

    return $string;
}

sub stopDaemon {
  my $self = shift;

  ## load PID
  my $s_pid = $self->getPID($_[0]);

  ## stop daemon
  ## actually no clean daemon shutdown is implemented
  ## if fork on the daemon not failed this should not be 
  ## a problem
  kill 9, $s_pid;

  $self->doLog ("killing SigningDaemon with PID ".$s_pid." at ".gmtime ()."\n"); 

  unlink $self->{SOCKET_FILE};

  return 1;
}

#####################################
##         client functions        ##
#####################################

sub get_xpath
{
  my $self = shift;

  ## check and fix the variables

  return $self->get_xpath_all (@_)
      if (wantarray);

  delete $self->{COUNTER}; 
  $self->_init (@_); 

  if (not $self->{FILENAME} or not $self->{XPATH}) {
    return undef;
  }
  if (ref ($self->{XPATH}) eq "ARRAY")
  {
      my @help;
      if (ref ($self->{COUNTER}) eq "ARRAY")
      {
          @help = @{$self->{COUNTER}};
      } else {
          @help = ($self->{COUNTER});
      }
      $self->{COUNTER} = ( @help, "0" )
          if (scalar @{$self->{XPATH}} > scalar @{$self->{COUNTER}});
  } else {
      $self->{COUNTER} = 0 if (not $self->{COUNTER});
  }

  ## prepare the message
  ##
  ## format   ::= filename . "\n" . element+ . \n
  ## element  ::= xpath . "\n" . counter . "\n" 
  ## 

  my $load .= $self->{FILENAME}."\n";
  if (ref ($self->{XPATH}) eq "ARRAY")
  {
    $self->{COUNTER} = [ reverse @{$self->{COUNTER}} ];
    foreach my $xpath (@{$self->{XPATH}})
    {
      $load .= $xpath."\n";
      $load .= pop (@{$self->{COUNTER}})."\n";
    }
  } else {
    $load .= $self->{XPATH}."\n";
    $load .= $self->{COUNTER}."\n";
  }
  $load .= "\n";
  $self->debug ("get_xpath: send message: $load");

  ## connect to socket

  $self->debug ("connect to socket $self->{SOCKET_FILE}");
  my $socket = $self->{SOCKET_FILE};
  socket(SOCK, PF_UNIX, SOCK_STREAM, 0) || return undef;
  connect(SOCK, sockaddr_un($socket))	|| return undef;

  ## send message

  $self->debug ("get_xpath: sending message");
  ## return undef if (not print SOCK $load);
  return undef if (not send (SOCK, $load, 0));
  shutdown (SOCK, 1);
  $load = "";
  
  ## read answer

  $self->debug ("get_xpath: reading answer");
  while (my $line = <SOCK>)
  {
      $load .= $line;
  }
  shutdown (SOCK, 0);
  
  $self->debug ("get_xpath: received info: $load");
  $self->debug ("all ok");
  $self->{USAGE_COUNTER}++;
  return $load;
}

sub get_xpath_all
{
    my $self = shift;
    my @result = ();
    my $help;
    my $counter = 0;

    my $keys = { @_ };
    if (not $keys->{COUNTER})
    {
        $keys->{COUNTER} = ();
    }
    if (ref ($keys->{COUNTER}) ne "ARRAY")
    {
        my $help = $keys->{COUNTER};
        delete $keys->{COUNTER};
        if (defined $help)
        {
            $keys->{COUNTER}->[0] = $help;
        } else {
            $keys->{COUNTER} = ();
        }
    }
    if (ref ($keys->{XPATH}) ne "ARRAY")
    {
        my $help = $keys->{XPATH};
        delete $keys->{XPATH};
        $keys->{XPATH}->[0] = $help;
    }

    push @{$keys->{COUNTER}}, $counter;
    while ($help = $self->get_xpath (
                       FILENAME => $keys->{FILENAME},
                       XPATH    => $keys->{XPATH},
                       COUNTER  => $keys->{COUNTER}))
    {
        pop @{$keys->{COUNTER}};
        $result [$counter++] = $help;
        push @{$keys->{COUNTER}}, $counter;
    }

    return @result;
}

sub get_xpath_count
{
    my $self = shift;
    my @result = ();
    my $help;
    my $counter = 0;

    my $keys = { @_ };
    if (not $keys->{COUNTER})
    {
        $keys->{COUNTER} = ();
    }
    if (ref ($keys->{COUNTER}) ne "ARRAY")
    {
        my $help = $keys->{COUNTER};
        delete $keys->{COUNTER};
        if (defined $help)
        {
            $keys->{COUNTER}->[0] = $help;
        } else {
            $keys->{COUNTER} = ();
        }
    }
    if (ref ($keys->{XPATH}) ne "ARRAY")
    {
        my $help = $keys->{XPATH};
        delete $keys->{XPATH};
        $keys->{XPATH}->[0] = $help;
    }

    push @{$keys->{COUNTER}}, "-1";
    $help = $self->get_xpath (
                       FILENAME => $keys->{FILENAME},
                       XPATH    => $keys->{XPATH},
                       COUNTER  => $keys->{COUNTER});

    return $help;
}

###############################################
##          additonal help functions         ##
###############################################

sub getPID
{
    my $self = shift;
 
    my $fifo = $_[0] if ($_[0]);
    $fifo = $self->{PIDFILE} if (not $fifo); 
 
    ## getting pid from PIDFILE
    if (not open (FD, "<".$fifo)) {
        return $openCA::XML::Cache::ERROR->{OPEN_PIDFILE_FAILED};
    }

    ## I don't know PIDs longer than 10 charcters
    my $s_pid;
    read (FD, $s_pid, 10);

    return int ($s_pid);
}

sub DESTROY
{
    my $self = shift;
}

1;
