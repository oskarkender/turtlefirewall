#======================================================================
# Turtle Firewall webmin module
#
# Copyright (c) Andrea Frigido
# You may distribute under the terms of either the GNU General Public
# License
#======================================================================

$|=1;

BEGIN { push(@INC, ".."); };
use WebminCore;
&init_config();

# if XML::Parser is not present
$gotXmlParser = 0;
foreach my $d (@INC) {
	if( -f "$d/XML/Parser.pm" ) {
		$gotXmlParser++;
		break;
	}
}
if( ! $gotXmlParser ) {
	&ui_print_header( undef, $text{'title'}, "" );
	print "<br><br><b>XML::Parser perl module is needed, please install it!</b><br>";
	print '<a href="/cpan/download.cgi?source=3&cpan=XML::Parser&mode=2">install XML::Parser from CPAN</a><br><br>';
	&ui_print_footer('/',$text{'index'});
	exit;
}

# do you need to install startup scripts?
if( -f "./setup/turtlefirewall" ) {
	&ui_print_header( undef, $text{'title'}, "" );
	print "<br>";
	print "<b>This is the first execution of Turtle Firewall, you need to install/update startup scripts.</b>\n";
	print "<br><br>";
	print &ui_form_start("setup.cgi","post");
	print &ui_submit("Install Turtle Firewall Startup scripts","install");
	print &ui_form_end();
	print "<br><b>Notes:</b> ";
	print "Remember to install xt_ndpi, xt_geoip and xt_ratelimit kernel modules.";
	#print "Remember to enable your Linux box to act as a router ";
	#print "(select \"Act as router\"=yes in Hardware->Network->Routing webmin form).";
	#print "<li>Remember to install XML::Parser Perl module</li>";
	print "<br>\n";
	&ui_print_footer('/',$text{'index'});
	exit;
}

my $tfwlib = '/usr/lib/turtlefirewall/TurtleFirewall.pm';
if( ! -f $tfwlib ) {
	&error( 'Turtle Firewall Library not found. Install Turtle Firewall.' );
}

if( -f $config{fw_logfile} ) {
	$SysLogFile = $config{fw_logfile};
} elsif( -f  "/var/log/messages" ) {
	$SysLogFile =  "/var/log/messages";
} elsif( -f  "/var/log/syslog" ) {
	$SysLogFile =  "/var/log/syslog";
}

$FlowLogFile = "/var/log/flowinfo.log";

require $tfwlib;
$fw = new TurtleFirewall();
if( -f $config{fw_file} ) {
	$fw->LoadFirewall( $config{fw_file} );
} else {
	$fw->LoadFirewall( "/etc/turtlefirewall/fw.xml" );
}

sub confdir {
	if( $config{fw_file} =~ /(.*)\// ) {
		return $1;
	} else {
		#return '/tmp';
		return '/etc/turtlefirewall';
	}
}

%flowreports = ( 
	'source' => { INDEX => '4' },
       	'destination' => { INDEX => '6' },
       	'dport' => { INDEX => '7' },
       	'protocol' => { INDEX => '16' },
       	'hostname' => { INDEX => '17' },
       	'risk' => { INDEX => '22' }
);

%blacklists = ( 
	'ip_blacklist' => { FILE => '/etc/turtlefirewall/ip_blacklist.dat', CRON => '/etc/cron.daily/ip_blacklist', DESCRIPTION => 'IP Address' },
	'domain_blacklist' => { FILE => '/etc/turtlefirewall/domain_blacklist.dat', CRON => '/etc/cron.daily/domain_blacklist', DESCRIPTION => 'DNS Domain Name' },
	'ja3_blacklist' => { FILE => '/etc/turtlefirewall/ja3_blacklist.dat', CRON => '/etc/cron.daily/ja3_blacklist', DESCRIPTION => 'SSL Handshake Fingerprint' },
	'sha1_blacklist' => { FILE => '/etc/turtlefirewall/sha1_blacklist.dat', CRON => '/etc/cron.daily/sha1_blacklist', DESCRIPTION => 'SSL Certificate Fingerprint' }
);

sub LoadServices {
	my $firewall = shift;
	my $fwservices_file = $config{'fwservices_file'};
	my $fwuserdefservices_file = $config{'fwuserdefservices_file'};

	if( ! -f $fwservices_file ) {
		$fwservices_file = "/etc/turtlefirewall/fwservices.xml";
	}
	if( ! -f $fwuserdefservices_file ) {
		$fwuserdefservices_file = "/etc/turtlefirewall/fwuserdefservices.xml";
	}
	$firewall->LoadServices( $fwservices_file, $fwuserdefservices_file );
}

sub LoadNdpiProtocols {
	my $firewall = shift;
	my $fwndpiprotocols_file = $config{'fwndpiprotocols_file'};

	if( ! -f $fwndpiprotocols_file ) {
		$fwndpiprotocols_file = "/etc/turtlefirewall/fwndpiprotocols.xml";
	}
	$firewall->LoadNdpiProtocols( $fwndpiprotocols_file );
}

sub LoadNdpiRisks {
	my $firewall = shift;
	my $fwndpirisks_file = $config{'fwndpirisks_file'};

	if( ! -f $fwndpirisks_file ) {
		$fwndpirisks_file = "/etc/turtlefirewall/fwndpirisks.xml";
	}
	$firewall->LoadNdpiRisks( $fwndpirisks_file );
}

sub LoadCountryCodes {
	my $firewall = shift;
	my $fwcountrycodes_file = $config{'fwcountrycodes_file'};

	if( ! -f $fwcountrycodes_file ) {
		$fwcountrycodes_file = "/etc/turtlefirewall/fwcountrycodes.xml";
	}
	$firewall->LoadCountryCodes( $fwcountrycodes_file );
}

# Generates html for service input
sub formService {
	my( $service, $port, $multiple ) = @_;
	my $this = '';

	my @services = split( /,/, $service );

	my $options_service = '';
	&LoadServices($fw);
	for my $k ($fw->GetServicesList()) {
		if( !($k =~ /^(tcp|udp|all)$/) ) {
			my %service = $fw->GetService($k);
			my $selected = 0;
			foreach my $s (@services) {
				if( $k eq $s ) {
					$selected = 1;
					last;
				}
			}
			$options_service .= qq~<option value="$k"~.($selected ? ' SELECTED' : '').">$k - $service{DESCRIPTION}</option>";
		}
	}

	$this .= '<table border="0" cellpadding="0">';
	$this .= '<tr><td><input type="RADIO" name="servicetype" value="1"'.($service eq 'all' ? ' CHECKED' : '')."></td><td>$text{rule_all_services}</td></tr>";

	$this .= '<tr><td><input type="RADIO" name="servicetype" value="2"'.(!($service =~ /^(tcp|udp|all)$/) ? ' CHECKED' : '').'></td>';
		if( $multiple ) {
	$this .= '<td><select name="service2" size="5" MULTIPLE>';
	} else {
		$this .= '<td><select name="service2" size="1">';
	}
	$this .= $options_service;
	$this .= '</select></td></tr>';

	$this .= '<tr><td><input type="RADIO" name="servicetype" value="3"'.($service =~ /^(tcp|udp)$/ ? ' CHECKED' : '').'></td>';
	$this .= '<td><select name="service3" size="1">';
	$this .= '<option'.($service eq 'tcp' ? ' SELECTED' : '').'>tcp</option>';
	$this .= '<option'.($service eq 'udp' ? ' SELECTED' : '').'>udp</option>';
	$this .= '</select>';
	$this .= " $text{rule_port} : <input type=\"TEXT\" name=\"port\" value=\"$port\" size=\"11\" maxlength=\"11\"> <small><i>$text{port_help}</i></small></td></tr></table>";
	return $this;
}

# Parse service inputs and return name of service choosed
sub formServiceParse {
	my ($servicetype, $service2, $service3, $port ) = @_;

	if( $servicetype == 1 ) {
		return ('all', '');
	} elsif( $servicetype == 2 ) {
		# specific service or service list
		$service2 =~ s/\0/,/g;
		return ($service2, '');
	} elsif( $servicetype == 3 ) {
		# generic tcp/udp service
		return ($service3, $port);
	}
	return ('','');
}

# Generates html for ndpiprotocol input
sub formNdpiProtocol {
	my( $ndpiprotocol, $category, $multiple ) = @_;
	my $this = '';

	my @ndpiprotocols = split( /,/, $ndpiprotocol );

	my @categorys = ();

	my $options_ndpiprotocol = '';
	&LoadNdpiProtocols($fw);
	for my $k ($fw->GetNdpiProtocolsList()) {
		if( !($k =~ /^(all)$/) ) {
			my %ndpiprotocol = $fw->GetNdpiProtocol($k);
			my $selected = 0;
			foreach my $n (@ndpiprotocols) {
				if( $k eq $n ) {
					$selected = 1;
					last;
				}
			}
			$options_ndpiprotocol .= qq~<option value="$k"~.($selected ? ' SELECTED' : '').">$k - $ndpiprotocol{CATEGORY}</option>";
			push(@categorys, $ndpiprotocol{CATEGORY});
		}
	}

	# sort
	@categorys = sort(@categorys);
	# unique values
	my $prev = '***none***';
	@categorys = grep($_ ne $prev && (($prev) = $_), @categorys);

	for my $k (@categorys) {
		my $selected = 0;
		if( $k eq $category ) { $selected = 1; }
		$options_category .= qq~<option value="$k"~.($selected ? ' SELECTED' : '').">$k";
	}

	$this .= '<table border="0" cellpadding="0">';
	$this .= '<tr><td><input type="RADIO" name="ndpiprotocoltype" value="1"'.($ndpiprotocol eq 'all' ? ' CHECKED' : '')."></td><td>$text{rule_all_ndpiprotocols}</td></tr>";

	$this .= '<tr><td><input type="RADIO" name="ndpiprotocoltype" value="2"'.(!($ndpiprotocol =~ /^(all)$/) ? ' CHECKED' : '').'></td>';
	if( $multiple ) {
		$this .= '<td><select name="ndpiprotocol2" size="5" MULTIPLE>';
	} else {
		$this .= '<td><select name="ndpiprotocol2" size="1">';
	}
	$this .= $options_ndpiprotocol;
	$this .= '</select></td></tr>';

	$this .= '<tr><td><input type="RADIO" name="ndpiprotocoltype" value="3"'.($category ne '' ? ' CHECKED' : '').'></td>';
	$this .= "<td>$text{category} : ";
	$this .= '<select name="category" size="1">';
	$this .= $options_category;
	$this .= '</select></td></tr></table>';
	return $this;
}

# Parse ndpiprotocol inputs and return name of ndpiprotocol choosen
sub formNdpiProtocolParse {
	my ($ndpiprotocoltype, $ndpiprotocol2, $category ) = @_;

	if( $ndpiprotocoltype == 1 ) {
		return ('all', '');
	} elsif( $ndpiprotocoltype == 2 ) {
		# specific ndpiprotocol or ndpiprotocol list
		$ndpiprotocol2 =~ s/\0/,/g;
		return ($ndpiprotocol2, '');
	} elsif( $ndpiprotocoltype == 3 ) {
		# ndpiprotocol category
		return ('', $category);
	}
	return ('','');
}

sub getOptionsList {
	@optionkeys = ('rp_filter','log_martians',
			'drop_invalid_state', 'drop_invalid_all', 'drop_invalid_none', 'drop_invalid_fin_notack',
			'drop_invalid_syn_fin', 'drop_invalid_syn_rst', 'drop_invalid_fragment',
		       	'drop_ip_blacklist', 'drop_domain_blacklist', 'drop_ja3_blacklist', 'drop_sha1_blacklist',
			'nf_conntrack_max', 'log_limit', 'log_limit_burst' );
	%options = ();
	%{$options{rp_filter}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>1 );
	%{$options{log_martians}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>1 );
	%{$options{drop_invalid_state}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_invalid_all}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_invalid_none}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_invalid_fin_notack}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_invalid_syn_fin}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_invalid_syn_rst}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_invalid_fragment}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_ip_blacklist}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_domain_blacklist}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_ja3_blacklist}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{drop_sha1_blacklist}} = ( 'type'=>'radio', 'default'=>'on', 'addunchangeopz'=>0 );
	%{$options{nf_conntrack_max}} = ( 'type'=>'text', 'default'=>262144, 'addunchangeopz'=>0 );
	%{$options{log_limit}} = ( 'type'=>'text', 'default'=>60, 'addunchangeopz'=>0 );
	%{$options{log_limit_burst}} = ( 'type'=>'text', 'default'=>5, 'addunchangeopz'=>0 );
}

sub roundbytes {
	my $bytes = shift;
	my $n = 0;
	++$n and $bytes /= 1024 until $bytes < 1024;
	return sprintf "%.1f %s", $bytes, ( qw[ B KB MB GB TB ] )[ $n ];
}

1;
