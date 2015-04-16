#!/usr/bin/perl

use utf8;
use warnings;
use strict;
use feature qw(say state);

use LWP;
use LWP::ConnCache;
use HTTP::Request::Common qw(POST);
use HTTP::Message;
use WWW::Mechanize::Firefox;
use Digest::SHA qw(sha512_base64);


my %config;
{
   open my $config, '<', '.lp.conf';
   foreach (<$config>) {
      next if m/\A\s++\Z/;

      if (m/([^\h]++)\h++=\h++(.++)/) {
         $config{$1} = $2
      } else {
         warn "Can't read config string $_\n"
      }
   }
   close $config;
}


sub send_sms {
   my $ua = LWP::UserAgent->new();
   my $token = $ua->get( 'http://sms.ru/auth/get_token' );
  
   my $req = POST 'http://sms.ru/sms/send',
   [
      api_id => $config{sms_id},
      login  => $config{sms_login},
      sha512 => sha512_base64( $config{sms_password}.$token.$config{sms_id} ),
      token  => $token,
      to     => $config{sms_phone},
      text   => "$_[0]"
   ];
   
   $ua->request( $req );
   
   return 0;
}

END {
	send_sms("EXIT");
}

my $mech = WWW::Mechanize::Firefox->new();
$mech->autoclose_tab( 0 );
$mech->autodie(0);


my $res;

$mech->get($config{kassir_login_page});
die( "login:" . $mech->status() . "\n" ) if !$mech->success();

$mech->submit_form(
	with_fields => {
		login    => $config{kassir_login},
		password => $config{kassir_password}
	}
);

die( "login:" . $mech->status() . "\n" ) if !$mech->success();


#for quick checks
my $ua = LWP::UserAgent->new();
$ua->timeout(10);

my $start_page = 0;

my $pause = 150;
my $count = 0;
#number of bilets to bye
my $b = 2;

while (1) {
	last if $b <= 0;

	my $num = '';
	my $cond = 0;

   if (!$start_page) {
		$mech->get($config{kassir_monitor_page});
		$start_page = 1;
	} else {
   	$mech->reload(1);
	}

	if ($mech->success()) {
		if ($mech->content =~ m/(fan|фан).*?href="(?<link>[^"]+)"/is) {
			send_sms("Go! Check it!");
			my $lp_fan_link = $+{link};

			say $lp_fan_link;

			$start_page = 0;
			$mech->get($lp_fan_link, synchronize => 1);
			if ($mech->success()) {
				if ($mech->content =~ m!(?<num>\d+)</span>\sпо\sцене!) {
					my $bn = 0;
					if ($b >= $+{num}) {
						$bn = $+{num};
					} else {
						$bn = $b;
					}
					say $bn;

					$mech->form_id('form_id_main');
					$mech->field('seats_5000.00' => $bn);
					$mech->click({name => 'sButton', synchoronize => 1});
					sleep 20;
					
					if ($mech->success()) {
						$mech->form_id('form_id_main');
						#$mech->click({ xpath => '//*[@id="form_id_main"]/table/tbody/tr[7]/td/div[2]/div[2]/input'});

						$mech->click({id => 'dt_176481190', synchronize => 0});
						$mech->click({id => 'offerta_agree', synchronize => 0});

						$mech->click_button(name => 'order_go');
					
						if ($mech->success()) {
							send_sms("Go! Check it! $bn reserved!");
						} else {
							send_sms("Probable last step fail.");
						}

					} else {
						send_sms("Go! Get it! Some problems with $bn bilets reservation.");
						warn "FAIL: Can't automatically reserve $bn bilets.\n"
					}
					
					$b -= $bn;
				} else {
					send_sms("Go! Get it! Can't parse num.");
					warn "FAIL: Can't parse number of fanzone bilets.\n"
				}
			} else {
				send_sms("Go! Get it!");
				warn "FAIL: Can't donwload fanzone page.\n"
			}
			$cond = 1;
		}
	} else {
			warn "FAIL: Can't download LP page.\n"
	}


	if (!($count++ % 10)) {
		$res = $ua->get('http://www.kassir.ru/msk/order/969626113-970191036.html');
		if ($res->is_success) {
			if ($res->decoded_content =~ m!(?<num>\d+)</span>\sпо\sцене!) {
				$num = "danceparter: $+{num}";
			} else {
				warn "FAIL: Can't parse number of danceparter bilets.\n"
			}
		} else {
			warn "FAIL: Can't download danceparter page.\n"
		}
	}
	
   my $time = sprintf("%02d:%02d:%02d", reverse ((localtime(time))[0 .. 2]));
	if ($cond) {
		say "$time HOORAY! $num";
	} else {
		say "$time NONE $num";
	}

   sleep $pause;
}

