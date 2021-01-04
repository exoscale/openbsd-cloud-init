#!/usr/bin/env perl

# Copyright (c) 2015 Pierre-Yves Ritschard

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

use CPAN::Meta::YAML;
use HTTP::Tiny;
use File::Basename;
use File::Path qw(make_path mkpath);
use File::Temp qw(tempfile);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use strict;

use constant {
    METADATA_HOST => "169.254.169.254",
};

sub get_data {
  my ($host, $path) = @_;
  my $response = HTTP::Tiny->new->get("http://$host/latest/$path");
  return unless $response->{success};
  return $response->{content};
}

sub get_default_fqdn {
  my $host = METADATA_HOST;

  my $local_hostname = get_data($host, 'meta-data/local-hostname');
  return $local_hostname . '.my.domain';
}

sub set_hostname {
  my $fqdn = shift;

  open my $fh, ">", "/etc/myname";
  printf $fh "%s\n", $fqdn;
  close $fh;
  system("hostname " . $fqdn);
}

sub install_pubkeys {
  my $pubkeys = shift;

  make_path('/root/.ssh', { verbose => 0, mode => 0700 });
  open my $fh, ">>", "/root/.ssh/authorized_keys";
  printf $fh "#-- key added by cloud-init at your request --#\n";
  printf $fh "%s\n", $pubkeys;
  close $fh;
}

sub apply_user_data {
  my $data = shift;

  if (defined($data->{fqdn})) {
    set_hostname $data->{fqdn};
  }

  if (defined($data->{manage_etc_hosts}) &&
      ($data->{manage_etc_hosts} eq 'true' ||
       $data->{manage_etc_hosts} eq 'localhost')) {
    open my $fh, ">>", "/etc/hosts";
    my $fqdn = $data->{fqdn} // get_default_fqdn;
    my ($shortname) = split(/\./, $fqdn);
    printf $fh "127.0.1.1 %s %s\n", $shortname, $fqdn;
    close $fh;
  }

  if (defined($data->{ssh_authorized_keys})) {
    install_pubkeys join("\n", @{ $data->{ssh_authorized_keys} });
  }

  if (defined($data->{packages})) {
    foreach my $package (@{ $data->{packages} }) {
      system("pkg_add " . $package);
    }
  }

  if (defined($data->{write_files})) {
    foreach my $item (@{ $data->{write_files} }) {
      mkpath [dirname($item->{path})], 0, 0755;
      open my $fh, ">", $item->{path};
      print $fh $item->{content};
      if (defined($item->{permissions})) {
        my $perms = oct($item->{permissions});
        chmod($perms, $fh);
      }
      if (defined($item->{owner})) {
        my ($user_name, $group_name) = split(/\:/, $item->{owner});
        my $uid = getpwnam $user_name;
        my $gid = getgrnam $group_name;
        chown $uid, $gid, $fh;
      }
      close $fh;
    }
  }

  if (defined($data->{runcmd})) {
    foreach my $runcmd (@{ $data->{runcmd} }) {
      system("sh -c \"$runcmd\"");
    }
  }
}

sub cloud_init {
    my $host = METADATA_HOST;

    my $compressed = get_data($host, 'user-data');
    my $data;
    gunzip \$compressed => \$data;

    my $pubkeys = get_data($host, 'meta-data/public-keys');
    chomp($pubkeys);
    install_pubkeys $pubkeys;
    set_hostname get_default_fqdn;

    if (defined($data)) {
        if ($data =~ /^#cloud-config/) {
            $data = CPAN::Meta::YAML->read_string($data)->[0];
            apply_user_data $data;
        } elsif ($data =~ /^#\!/) {
            my ($fh, $filename) = tempfile("/tmp/cloud-config-XXXXXX");
            print $fh $data;
            chmod(0700, $fh);
            close $fh;
            system("sh -c \"$filename && rm $filename\"");
        }
    }
}

sub action_deploy {
    #-- rc.firsttime stub
    open my $fh, ">>", "/etc/rc.firsttime";
    print $fh <<'EOF';
# run cloud-init
path=/usr/local/libdata/cloud-init.pl
echo -n "exoscale first boot: "
perl $path cloud-init && echo "done."
EOF
    close $fh;

    #-- remove generated keys and seeds
    unlink glob "/etc/ssh/ssh_host*";
    unlink "/etc/random.seed";
    unlink "/var/db/host.random";
    unlink "/etc/isakmpd/private/local.key";
    unlink "/etc/isakmpd/local.pub";
    unlink "/etc/iked/private/local.key";
    unlink "/etc/isakmpd/local.pub";

    #-- remove cruft
    unlink "/tmp/*";
    unlink "/var/db/dhclient.leases.vio0";

    #-- disable root password
    system("chpass -a 'root:*:0:0:daemon:0:0:Charlie &:/root:/bin/ksh'")
}

#-- main
my ($action) = @ARGV;

action_deploy if ($action eq 'deploy');
cloud_init if ($action eq 'cloud-init');
