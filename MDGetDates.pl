#!/usr/bin/perl -w
#=====================================================================
#
# 	FILE:			MDGetDates.pl
#
#	USAGE:			perl MDGetDates.pl
#
#	DESCRIPTION:	This script can output the dates required as parameters
#					for certain CA jobs
#
#	OPTIONS:		?
#	REQUIREMENTS:	?
#
#	NOTES:			
#	AUTHOR:			Louis Amstutz
#	COMPANY:  		CMAH
#	VERSION:		1.0
#	CREATED:		04/28/2011
#	REVISION:		11/14/2011
#=====================================================================
use warnings;
use strict;
use XML::Simple;
use POSIX;

$ENV{TZ}="EST";
my $working_dir = $0;
my $secondsInDay = 86400;

if ($^O =~ /Win32/) {
	$working_dir =~ s/scripts\\MDGetDates.pl$//ig;
}
else {
	$working_dir =~ s/scripts\/MDGetDates.pl$//ig;
}

my $logfile = $working_dir . "logs/MDGetDates.log";
my $configfile = $working_dir . "config/MDGetDates.config";
my $holidaysfile = $working_dir . "config/DateManipHolidays.config";

my $xml = new XML::Simple;
my $data = $xml->XMLin($configfile);
my $paramFile = $data->{ParamFile};
my $quarterDates = $data->{QuarterDates}->{Quarter};
my @holidays;

sub logit {
	my ($file, $message) = @_;
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	print $file sprintf("%04d/%02d/%02d %02d:%02d - $message\n", $year+1900, $mon+1, $mday, $hour, $min);
}

sub formatDate {
	my ($time) = @_;
	
	my ($y,$m,$d) = (localtime($time))[5,4,3];
	$y += 1900;
	$m += 1;

	my $returnString = $y;
	if ($m < 10) {$returnString .= "0";}
	$returnString .= $m;
	if ($d < 10) {$returnString .= "0";}
	$returnString .= $d;

	return $returnString;
}

sub addBusinessDays {
	my ($time, $daysToAdd) = @_;
	
	my ($d, $m, $y) = (localtime($time))[3,4,5];
	my $time2 = mktime(0,0,0,$d,$m,$y);#make sure time is midnight is it matches holidays epoche
	
	my $count = 0;
	while ($count <= $daysToAdd) {
		my ($wd) = (localtime($time2))[6];
		my $isBusinessDay = 1;
		if ($wd < 6 && $wd > 0) {
			foreach (@holidays) {
				if ($time2 == $_) {
					$isBusinessDay = 0;
					last;
				}
			}
		}
		else {$isBusinessDay = 0;}
		if ($isBusinessDay) {
			$count++;
		}
		$time2 += $secondsInDay;
		
	}
	$time2 -= $secondsInDay;
	return $time2;
}

sub createHolidays {
	my ($y) = @_;

	my $holdayStrings = $data->{Holidays}->{holiday};
	foreach (@$holdayStrings) {
		my $time;
		if ($_ eq "easter") {
			$time = CalculateEaster($y)-(2 * $secondsInDay);#good friday
		}
		else {
			my ($m, $d) = split(/\//, $_);
			
			if (substr($d,0,1) eq "m") {# nth monday of the month
				my $nthMonday = substr($d,1,2) - 1;
				$time = mktime(0,0,0,1,$m-1,$y-1900);
				
				my $wd = (localtime($time))[6];
				my $daysToAdd = ((8 - $wd)%7) + ($nthMonday * 7);
				$time += $daysToAdd * $secondsInDay;
			}
			elsif (substr($d,0,1) eq "b") {# monday before nth day
				my $endDay = substr($d,1,2);
				$time = mktime(0,0,0,$endDay,$m-1,$y-1900);
				my $wd = (localtime($time))[6];
				my $daysToSubtract = (($wd+6)%7);
				$time -= $daysToSubtract * $secondsInDay;
			}
			else {
				$time = mktime(0,0,0,$d,$m-1,$y-1900);
			}
		}
		push(@holidays, $time);
	}
}

sub CalculateEaster {
	my ($year) = @_;
	my $Century = int $year / 100;
	my $G = $year % 19;
	my $K = int (($Century - 17) / 25);
	my $I = ($Century - int ($Century / 4) - int (($Century - $K) / 3) + 19 * $G + 15) % 30;
	$I = $I - (int ($I / 28)) * (1 - (int ($I / 28)) * (int (29 / ($I + 1))) * (int ((21 - $G) / 11)));
	my $J = ($year + int ($year / 4) + $I + 2 - $Century + int ($Century / 4)) % 7;
	my $L = $I - $J;
	
	my $EasterMonth = 3 + int (($L + 40) / 44);
	my $EasterDay = $L + 28 - 31 * (int ($EasterMonth / 4));
	
	return mktime(0,0,0,$EasterDay,$EasterMonth-1,$year-1900);
}

sub lastFridayOfMonth {
	my ($y, $m) = @_;
	
	my $nextMonth = $m + 1;
	my $nextMonthYear = $y;
	if ($nextMonth == 13) {
		$nextMonth = 1;
		$nextMonthYear++;
	}
	
	my $time = mktime(0,0,0,1,$nextMonth-1,$nextMonthYear-1900);
	my $wd = (localtime($time))[6];
	my $daysBack = (2 + $wd) % 7;
	if ($daysBack == 0) {$daysBack = 7;}
	
	return $time - ($daysBack * $secondsInDay);
}


my $log;
open($log, ">>", $logfile) or die "Failed to open log file\n";


my $dateType = $ARGV[0];
if (@ARGV != 1 || ($dateType ne "PreviousQuarterStart" && $dateType ne "PreviousQuarterEnd" && $dateType ne "3rdBusinessDay") &&
	$dateType ne "WelcomeStart" && $dateType ne "WelcomeEnd" && $dateType ne "DailyAccrualStart" && $dateType ne "DailyAccrualEnd") {
	logit($log, "Usage: MDGetDates.pl <PreviousQuarterStart|PreviousQuarterEnd|3rdBusinessDay|WelcomeStart|WelcomeEnd|DailyAccrualStart|DailyAccrualEnd>");
	die;
}

if ($dateType eq "start") {$dateType = "PreviousQuarterStart";}
if ($dateType eq "end") {$dateType = "PreviousQuarterEnd";}

my ($hour, $day, $month, $year, $weekDay) = (localtime(time))[2,3,4,5,6];
$year += 1900;
$month += 1;
createHolidays($year);
if ($ARGV[0] eq "3rdBusinessDay") {
	my $firstOfMonth = mktime(0,0,0,1,$month-1,$year-1900);
	my $thirdBusi = addBusinessDays($firstOfMonth, 2);

	print formatDate($thirdBusi);
}
elsif ($dateType eq "PreviousQuarterStart" || $dateType eq "PreviousQuarterEnd") {
	my $lastQuarter;
	if ($month >= 1 && $month < 4) {
		$lastQuarter = 3;
		$year--;
	}
	elsif ($month >= 4 && $month < 7) {$lastQuarter = 0;}
	elsif ($month >= 7 && $month < 10) {$lastQuarter = 1;}
	elsif ($month >= 10 && $month < 13) {$lastQuarter = 2;}
	else {
		logit($log, "Unknown Error initializing quarter");
		die;
	}

	my $returnDate;
	if ($dateType eq "PreviousQuarterStart") {$returnDate = $year . $quarterDates->[$lastQuarter]->{start};}
	elsif ($dateType eq "PreviousQuarterEnd") {$returnDate = $year . $quarterDates->[$lastQuarter]->{end};}

	print $returnDate;
}
elsif ($dateType eq "DailyAccrualStart"){
	my $nextBusi;
	my $stillLooking = 1;

	my $currentDate = mktime(0,0,0,$day,$month-1,$year-1900);
	while ($stillLooking) {
		my $lastFriday = lastFridayOfMonth($year, $month);
		$nextBusi = addBusinessDays($lastFriday, 1);
		if ($currentDate < $nextBusi) {
			$month -= 1;
			if ($month == 0) {
				$month = 12;
				$year -= 1;
			}
		}
		else {
			$stillLooking = 0;
		}
	}
	
	print formatDate($nextBusi);
}
elsif ($dateType eq "DailyAccrualEnd"){
	my $date = mktime(0,0,0,$day,$month-1,$year-1900);
	
	if ($hour < 11) {
		$date -= $secondsInDay;
	}
	print formatDate($date);
}
elsif ($dateType eq "WelcomeStart"){
	my $date = mktime(0,0,0,$day,$month-1,$year-1900);
	my $daysBack = (2 + $weekDay) % 7;
	if ($daysBack == 0) {$daysBack = 7;}
	$date -= $daysBack * $secondsInDay;
	print formatDate($date);
}
elsif ($dateType eq "WelcomeEnd"){
	my $date = mktime(0,0,0,$day,$month-1,$year-1900);
	print formatDate($date);
}

logit($log, "Success");
close $log;
