########################################################################################
#
# $Id: 20_FRM_IN.pm 16012 2018-01-27 20:11:34Z jensb $
#
# FHEM module for one Firmata digial input pin
#
########################################################################################
#
#  LICENSE AND COPYRIGHT
#
#  Copyright (C) 2013 ntruchess
#  Copyright (C) 2018 jensb
#
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
########################################################################################

package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not already included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "alarm" => "",
  "count" => 0,
);

my %gets = (
  "reading" => "",
  "state"   => "",
  "count"   => 0,
  "alarm"   => "off"
);

sub
FRM_IN_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_IN_Set";
  $hash->{GetFn}     = "FRM_IN_Get";
  $hash->{AttrFn}    = "FRM_IN_Attr";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_IN_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";

  $hash->{AttrList}  = "IODev count-mode:none,rising,falling,both count-threshold reset-on-threshold-reached:yes,no internal-pullup:on,off activeLow:yes,no $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_IN_PinModePullupSupported($)
{
  my ($hash) = @_;
  my $iodev = $hash->{IODev};
  my $pullupPins = defined($iodev)? $iodev->{pullup_pins} : undef;

  return defined($pullupPins);
}

sub
FRM_IN_Init($$)
{
	my ($hash,$args) = @_;
	if (FRM_IN_PinModePullupSupported($hash)) {
		my $pullup = AttrVal($hash->{NAME},"internal-pullup","off");
		my $ret = FRM_Init_Pin_Client($hash,$args,defined($pullup) && ($pullup eq "on")? PIN_PULLUP : PIN_INPUT);
		return $ret if (defined $ret);
		eval {
			my $firmata = FRM_Client_FirmataDevice($hash);
			my $pin = $hash->{PIN};
			$firmata->observe_digital($pin,\&FRM_IN_observer,$hash);
		};
		return FRM_Catch($@) if $@;
	} else {
		my $ret = FRM_Init_Pin_Client($hash,$args,PIN_INPUT);
		return $ret if (defined $ret);
		eval {
			my $firmata = FRM_Client_FirmataDevice($hash);
			my $pin = $hash->{PIN};
			if (defined (my $pullup = AttrVal($hash->{NAME},"internal-pullup",undef))) {
				$firmata->digital_write($pin,$pullup eq "on" ? 1 : 0);
			}
			$firmata->observe_digital($pin,\&FRM_IN_observer,$hash);
		};
		return FRM_Catch($@) if $@;
	}
	if (! (defined AttrVal($hash->{NAME},"stateFormat",undef))) {
		$main::attr{$hash->{NAME}}{"stateFormat"} = "reading";
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_IN_observer
{
	my ($pin,$old,$new,$hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name,5,"onDigitalMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--");
	if (AttrVal($hash->{NAME},"activeLow","no") eq "yes") {
		$old = $old == PIN_LOW ? PIN_HIGH : PIN_LOW if (defined $old);
		$new = $new == PIN_LOW ? PIN_HIGH : PIN_LOW;
	}
	my $changed = ((!(defined $old)) or ($old != $new));
	main::readingsBeginUpdate($hash);
	if ($changed) {
  	if (defined (my $mode = main::AttrVal($name,"count-mode",undef))) {
  		if (($mode eq "both")
  		or (($mode eq "rising") and ($new == PIN_HIGH))
  		or (($mode eq "falling") and ($new == PIN_LOW))) {
  	    	my $count = main::ReadingsVal($name,"count",0);
  	    	$count++;
  	    	if (defined (my $threshold = main::AttrVal($name,"count-threshold",undef))) {
  	    		if ( $count > $threshold ) {
  	    			if (AttrVal($name,"reset-on-threshold-reached","no") eq "yes") {
  	    			  $count=0;
  	    			  main::readingsBulkUpdate($hash,"alarm","on",1);
  	    			} elsif ( main::ReadingsVal($name,"alarm","off") ne "on" ) {
  	    			  main::readingsBulkUpdate($hash,"alarm","on",1);
  	    			}
  	    		}
  	    	}
  	    	main::readingsBulkUpdate($hash,"count",$count,1);
  	    }
  	};
	}
	main::readingsBulkUpdate($hash,"reading",$new == PIN_HIGH ? "on" : "off", $changed);
	main::readingsEndUpdate($hash,1);
}

sub
FRM_IN_Set
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];
  COMMAND_HANDLER: {
    $command eq "alarm" and do {
      return undef if (!($value eq "off" or $value eq "on"));
      main::readingsSingleUpdate($hash,"alarm",$value,1);
      last;
    };
    $command eq "count" and do {
      main::readingsSingleUpdate($hash,"count",$value,1);
      last;
    };
  }
}

sub
FRM_IN_Get($)
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "reading" and do {
      eval {
        return FRM_Client_FirmataDevice($hash)->digital_read($hash->{PIN}) == PIN_HIGH ? "on" : "off";
      };
      return $@;
    };
    ( $cmd eq "count" or $cmd eq "alarm" or $cmd eq "state" ) and do {
      return main::ReadingsVal($name,"count",$gets{$cmd});
    };
  }
  return undef;
}

sub
FRM_IN_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  my $pin = $hash->{PIN};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            FRM_Client_AssignIOPort($hash,$value);
            FRM_Init_Client($hash) if (defined ($hash->{IODev}));
          }
          last;
        };
        $attribute eq "count-mode" and do {
          if ($value ne "none" and !defined main::ReadingsVal($name,"count",undef)) {
            main::readingsSingleUpdate($main::defs{$name},"count",$sets{count},1);
          }
          last;
        };
        $attribute eq "reset-on-threshold-reached" and do {
          if ($value eq "yes"
          and defined (my $threshold = main::AttrVal($name,"count-threshold",undef))) {
            if (main::ReadingsVal($name,"count",0) > $threshold) {
              main::readingsSingleUpdate($main::defs{$name},"count",$sets{count},1);
            }
          }
          last;
        };
        $attribute eq "count-threshold" and do {
          if (main::ReadingsVal($name,"count",0) > $value) {
            main::readingsBeginUpdate($hash);
            if (main::ReadingsVal($name,"alarm","off") ne "on") {
              main::readingsBulkUpdate($hash,"alarm","on",1);
            }
            if (main::AttrVal($name,"reset-on-threshold-reached","no") eq "yes") {
              main::readingsBulkUpdate($main::defs{$name},"count",0,1);
            }
            main::readingsEndUpdate($hash,1);
          }
          last;
        };
        $attribute eq "internal-pullup" and do {
          if ($main::init_done) {
            my $firmata = FRM_Client_FirmataDevice($hash);
            if (FRM_IN_PinModePullupSupported($hash)) {
              $firmata->pin_mode($pin,$value eq "on"? PIN_PULLUP : PIN_INPUT);
            } else {
              $firmata->digital_write($pin,$value eq "on" ? 1 : 0);
              #ignore any errors here, the attribute-value will be applied next time FRM_IN_init() is called.
            }
          }
          last;
        };
        $attribute eq "activeLow" and do {
          my $oldval = AttrVal($hash->{NAME},"activeLow","no");
          if ($oldval ne $value) {
            $main::attr{$hash->{NAME}}{activeLow} = $value;
            if ($main::init_done) {
              my $firmata = FRM_Client_FirmataDevice($hash);
              FRM_IN_observer($pin,undef,$firmata->digital_read($pin),$hash);
            }
          };
          last;
        };
      }
    } elsif ($command eq "del") {
      ARGUMENT_HANDLER: {
        $attribute eq "internal-pullup" and do {
          my $firmata = FRM_Client_FirmataDevice($hash);
          if (FRM_IN_PinModePullupSupported($hash)) {
            $firmata->pin_mode($pin,PIN_INPUT);
          } else {
            $firmata->digital_write($pin,0);
          }
          last;
        };
        $attribute eq "activeLow" and do {
          if (AttrVal($hash->{NAME},"activeLow","no") eq "yes") {
            delete $main::attr{$hash->{NAME}}{activeLow};
            my $firmata = FRM_Client_FirmataDevice($hash);
            FRM_IN_observer($pin,undef,$firmata->digital_read($pin),$hash);
          };
          last;
        };
      }
    }
  };
  if (my $error = FRM_Catch($@)) {
    $hash->{STATE} = "error setting $attribute to $value: ".$error;
    return "cannot $command attribute $attribute to $value for $name: ".$error;
  }
}

1;

=pod

  CHANGES

  03.01.2018 jensb
    o implemented Firmata 2.5 feature PIN_MODE_PULLUP (requires perl-firmata 0.64 or higher)

=cut

=pod
=item device
=item summary Firmata: digital input
=item summary_DE Firmata: digitaler Eingang
=begin html

<a name="FRM_IN"></a>
<h3>FRM_IN</h3>
<ul>
  This module represents a pin of a <a href="http://www.firmata.org">Firmata device</a>
  that should be configured as a digital input.<br><br>

  Requires a defined <a href="#FRM">FRM</a> device to work. The pin must be listed in
  the internal reading <a href="#FRMinternals">"input_pins" or "pullup_pins"</a><br>
  of the FRM device (after connecting to the Firmata device) to be used as digital input with or without pullup.<br><br>

  <a name="FRM_INdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_IN &lt;pin&gt;</code> <br>
  Defines the FRM_IN device. &lt;pin&gt> is the arduino-pin to use.
  </ul>

  <br>
  <a name="FRM_INset"></a>
  <b>Set</b><br>
  <ul>
    <li>alarm on|off<br>
    set the alarm to on or off. Used to clear the alarm.<br>
    The alarm is set to 'on' whenever the count reaches the threshold and doesn't clear itself.</li>
  </ul><br>

  <a name="FRM_INget"></a>
  <b>Get</b>
  <ul>
    <li>reading<br>
    returns the logical state of the arduino-pin. Values are 'on' and 'off'.<br></li>
    <li>count<br>
    returns the current count. Contains the number of toggles of the arduino-pin.<br>
    Depending on the attribute 'count-mode' every rising or falling edge (or both) is counted.</li>
    <li>alarm<br>
    returns the current state of 'alarm'. Values are 'on' and 'off' (Defaults to 'off')<br>
    'alarm' doesn't clear itself, has to be set to 'off' explicitly.</li>
    <li>state<br>
    returns the 'state' reading</li>
  </ul><br>

  <a name="FRM_INattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>activeLow &lt;yes|no&gt;</li>
      <li>count-mode none|rising|falling|both<br>
      Determines whether 'rising' (transitions from 'off' to 'on') of falling (transitions from 'on' to 'off')<br>
      edges (or 'both') are counted. Defaults to 'none'</li>
      <li>count-threshold &lt;number&gt;<br>
      sets the theshold-value for the counter. Whenever 'count' reaches the 'count-threshold' 'alarm' is<br>
      set to 'on'. Use 'set alarm off' to clear the alarm.</li>
      <li>reset-on-threshold-reached yes|no<br>
      if set to 'yes' reset the counter to 0 when the threshold is reached (defaults to 'no').
      </li>
      <li>internal-pullup on|off<br>
      allows to switch the internal pullup resistor of arduino to be en-/disabled. Defaults to off.
      </li>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
  </ul><br>

  <a name="FRM_INnotes"></a>
  <b>Notes</b><br>
  <ul>
      <li>attribute <i>stateFormat</i><br>
      In most cases it is a good idea to assign "reading" to the attribute <i>stateFormat</i>. This will show the state
      of the pin in the web interface.
      </li>
  </ul>
</ul><br>

=end html
=cut
