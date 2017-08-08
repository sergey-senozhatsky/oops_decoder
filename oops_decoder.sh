#!/usr/bin/perl

#
# Copyright (C) 2017 Sergey Senozhatsky
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA
#

use strict;
use warnings;

use Data::Dumper;

my $OBJDUMP="arm-none-eabi-objdump";
my $ADDR2LINE="arm-none-eabi-addr2line";
my $current_cpu = -1;

sub decode_reg($$$)
{
	my $reg = shift;
	my $addrline = shift;
	my $reg_name = shift;

	my $asm = undef;

	$asm = `$OBJDUMP -d vmlinux | grep -A2 -B4 $reg:`;

	if (defined($asm)) {
		$asm =~ s/\n/\n\t\t/g;

		printf "\tASM:\n\n\t\t";
		print $asm;
		print "\n";
	} else {
		printf "\nWARNING: can't decode registry $reg_name [<$reg>]\n";
		return -1;
	}

	my $file = undef;
	my $line_num = undef;

	$file = $1, $line_num = $2 if $addrline =~ m/.+ at (.+):(\d+)/;
	if (defined($file) && defined($line_num)) {
		my $line_num_s = $line_num - 5;
		my $cnt = 0;
		$line_num_s = 0 if $line_num_s < 0;

		printf "\n\tSRC:\n\n";
		while ($cnt < 10) {
			my $src = $line_num_s." ".`awk 'FNR>=$line_num_s && FNR<=$line_num_s' $file`;

			if (defined($src)) {
				printf "\t\t";
				print $src;
			}

			$line_num_s++;
			$cnt++;
		}

		printf "\n\n";

	} else {
		printf "\nINFO: no corresponding source code could be found for $reg_name [<$reg>]\n";
	}

	return 0;
}

sub process_log($)
{
	my $stream = shift;
	my $cpu_header = 0;

	while (my $ln = <$stream>) {
		chomp $ln;
		
		my $time;
		my $_ncpu = -2;

		my $pc = undef;
		my $lr = undef;

		$_ncpu = $1, $time = $2 if $ln =~ m/^\[(\d{1})-(\d+\.\d+)\].*/;
		$current_cpu = $_ncpu, print "\n----------------------\n" if $current_cpu != $_ncpu;

		$pc = $1, $lr = $2 if $ln =~ m/Function entered at \[<(.+)>\] from \[<(.+)>\]/;

		printf "\n\n" if $ln =~ m/Backtrace:/;

		if (!defined($pc) && !defined($lr)) {
			$pc = $1, $lr = $2 if $ln =~ m/pc : \[<(.+)>\]    lr : \[<(.+)>\]/;
			
			$cpu_header++, printf "\n<--- OOPS CPU STATE BEGIN --->\n" if (defined($pc) && defined($lr));
		}

		if (defined($pc) && defined($lr)) {
			my $dpc = undef;;
			my $dlr = `$ADDR2LINE -e vmlinux -p -f -C $lr`;

			if ($cpu_header == 0) {
				$dpc = `$ADDR2LINE -e vmlinux -p -f -C -i $pc`;
			} else {
				printf $ln."\n";
				$dpc = `$ADDR2LINE -e vmlinux -p -f -C $pc`;
			}

			$dpc =~ s/\n/\n\t/g;
			$dlr =~ s/\n/\n\t\t/g;

			printf "[$current_cpu-$time] frame $pc ";
			printf "$dpc\n";

			decode_reg($pc, $dpc, "PC") if $cpu_header;

			printf "\t  was called by $lr $dlr\n";

			decode_reg($lr, $dlr, "LR");
			printf "<--- OOPS CPU STATE END  --->\n" if $cpu_header != 0;
		} else {
			printf $ln."\n";
		}

		$cpu_header = 0;
	}

	return 0;
}

my $stream = shift @ARGV;

my $stream_handle;
my $is_stdin = 0;

if (defined $stream) {
	open $stream_handle, "<", $stream or die $!;
} else {
	$stream_handle = *STDIN;
	$is_stdin++;
}

process_log($stream_handle);
close $stream_handle unless $is_stdin;
