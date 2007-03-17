=pod

=head1 NAME

Term::Shelly - Yet Another Shell Kit for Perl

=head1 VERSION

$Id$

=head1 GOAL

I needed a shell kit for an aim client I was writing. All of the Term::ReadLine modules are do blocking reads in doing their readline() functions, and as such are entirely unacceptable. This module is an effort on my part to provide the advanced functionality of great ReadLine modules like Zoid into a package that's more flexible, extendable, and most importantly, allows nonblocking reads to allow other things to happen at the same time.

=head1 NEEDS

 - Settable key bindings
 - history
 - vi mode (Yeah, I lub vi)

=head1 DONE

 - Callback for 'anykey'
 - Tab completion
 - Support for window size changes (sigwinch)
 - movement/in-line editing.
 - Completion function calls
 - Settable callbacks for when we have an end-of-line (EOL binding?)

=cut

package Term::Shelly;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.2';

# Default perl modules...
use IO::Select;
use IO::Handle; # I need flush()... or do i?;

# Get these from CPAN
use Term::ReadKey;

# Useful constants we need...

# for find_word_bound()
use constant WORD_BEGINNING => 1;     # look for the beginning of this word.
use constant WORD_END => 2;           # look for end of the word.
use constant WORD_NEXT => 4;          # look for beginning of next word
use constant WORD_ONLY => 8;          # Trailing spaces are important.
use constant WORD_REGEX => 16;         # I want to specify my own regexp

# for vi_jumpchar()
use constant JUMP_BACKCHARTO => 000;  # 'T' in vi (backwards)
use constant JUMP_BACKCHAR   => 001;  # 'F' in vi (backwards)
use constant JUMP_CHARTO     => 010;  # 't' in vi (forwards)
use constant JUMP_CHAR       => 011;  # 'f' in vi (forwards)

# Some key constant name mappings.
# I definately need a function to do this and some sort of hash returned which
# specifies the key pressed and any modifiers too.
# Like... ctrl+f5 is \e[15;5~ ... and not on all systems.
my %KEY_CONSTANTS = (
							"\e[A"      => "UP",
							"\e[B"      => "DOWN",
							"\e[C"      => "RIGHT",
							"\e[D"      => "LEFT",
						  );

# stty raw, basically
ReadMode 3;

# I need to know how big the terminal is (columns, anyway)

=pod

=head1 DESCRIPTION

=over 4

=cut

sub new ($) {
	my $class = shift;

	my $self = {
		"input_line" => "",
		"input_position" => 0,
		"input_prompt" => "",
		"leftcol" => 0,
		"echo" => 1,
		"vi_mode" => 0,
		"mode" => "insert",
	};

	bless $self, $class;

	($self->{"termcols"}) = GetTerminalSize();
	$SIG{WINCH} = sub { ($self->{"termcols"}) = GetTerminalSize(); $self->fix_inputline() };
	$SIG{CONT} = sub { ReadMode 3; $self->fix_inputline; };

	$self->{"select"} = new IO::Select(\*STDIN);

	my $bindings = {
		"ANYKEY"      => "anykey",
		"LEFT"        => "backward-char",
		"RIGHT"       => "forward-char",
		"UP"          => "up-history",
		"DOWN"        => "down-history",

		"BACKSPACE"   => "delete-char-backward",
		"^H"          => "delete-char-backward",
		"^?"          => "delete-char-backward",
		"^W"          => "delete-word-backward",

		"^U"          => "kill-line",

		"^J"          => "newline",
		"^M"          => "newline",

		"^A"          => "beginning-of-line",
		"^E"          => "end-of-line",
		"^K"          => "kill-to-eol",
		"^L"          => "redraw",

		"^I"          => "complete-word",
		"TAB"         => "complete-word",

		#"^T"          => "expand-line",

		#--------------------------------
		# vi bindings
		#

		# -------- DIRECTIONS

		"vi_h"           => "vi-backward-char",                  # DONE
		"vi_l"           => "vi-forward-char",                   # DONE
		"vi_k"           => "vi-up-history",
		"vi_j"           => "vi-down-history",

		"vi_w"           => "vi-forward-word",                   # DONE
		"vi_W"           => "vi-forward-whole-word",             # DONE
		"vi_e"           => "vi-end-word",                       # DONE
		"vi_E"           => "vi-end-whole-word",                 # DONE
		"vi_t"           => "vi-forward-charto", 
		"vi_T"           => "vi-backward-charto",
		"vi_f"           => "vi-forward-charat",
		"vi_F"           => "vi-backward-charat",
		"vi_G"           => "vi-history-goto",
		"vi_b"           => "vi-beginning-word",
		"vi_B"           => "vi-beginning-whole-word",,
		"vi_n"           => "vi-search-next",
		"vi_N"           => "vi-search-prev",
		"vi_'"           => "vi-mark-goto",
		'vi_$'           => "vi-end-of-line",
		"vi_^"           => "vi-beginning-of-line",

		# -------- INSERTION
   
		"vi_i"           => "vi-insert",
		"vi_I"           => "vi-insert-at-bol",
		"vi_a"           => "vi-add",
		"vi_A"           => "vi-add-at-eol",
		"vi_r"           => "vi-replace-char",
		"vi_R"           => "vi-replace-mode",
		"vi_s"           => "vi-substitute-char",
		"vi_S"           => "vi-substitute-line",
		#"vi_o" 
		#"vi_O"
		"vi_c"           => "vi-change",
		"vi_C"           => "vi-change-to-eol",

		#"vi_y"           => "vi-yank-direction",
		#"vi_Y"           => "vi-yank-to-eol",
		#"vi_u"           => "vi-undo",
		#"vi_p"           => "vi-paste-at",
		#"vi_P"           => "vi-paste-before",
		"vi_x"           => "vi-delete-char-backward",
		"vi_X"           => "vi-delete-char-forward",
		"vi_d"           => "vi-delete",

		# -------- OTHER COMMANDS

		"vi_m"           => "vi-mark",

	};

	my $mappings = {
		"anykey"                 => [ \&anykey ],
		"backward-char"          => [ \&backward_char ],
		"forward-char"           => [ \&forward_char ],
		"delete-char-backward"   => [ \&delete_char_backward ],
		"kill-line"              => [ \&kill_line ],
		"newline"                => [ \&newline ],
		"redraw"                 => [ \&fix_inputline ],
		"beginning-of-line"      => [ \&beginning_of_line ],
		"end-of-line"            => [ \&end_of_line ],
		"delete-word-backward"   => [ \&delete_word_backward ],

		"complete-word"          => [ \&complete_word ],
		#"expand-line"            => [ \&expand_line ],

		# ----------------------------------------------------------- vi mappings
		"vi-backward-char"       => [ \&vi_backward_char ],
		"vi-forward-char"        => [ \&vi_forward_char ],
		"vi-forward-word"        => [ \&vi_forward_word ],
		"vi-forward-whole-word"  => [ \&vi_forward_whole_word ],
		"vi-beginning-word"      => [ \&vi_beginning_word ],
		"vi-beginning-whole-word" => [ \&vi_beginning_whole_word ],
		"vi-end-of-line"         => [ \&vi_eol ],
		"vi-beginning-of-line"   => [ \&vi_bol ], 
		"vi-forward-charto"      => [ \&vi_forward_charto ],
		"vi-forward-charat"        => [ \&vi_forward_charat ],
		"vi-backward-charto"     => [ \&vi_backward_charto ],
		"vi-backward-charat"       => [ \&vi_backward_charat ],

		"vi-end-word"            => [ \&vi_end_word ],
		"vi-end-whole-word"      => [ \&vi_end_whole_word ],
		"vi-insert"              => [ \&vi_insert ],
		"vi-insert-at-bol"       => [ \&vi_insert_at_bol ],,
		"vi-add"                 => [ \&vi_add ],
		"vi-add-at-eol"          => [ \&vi_add_at_eol ],

		"vi-delete-char-backward" => [ \&vi_delete_char_backward ],
		"vi-delete-char-forward"  => [ \&vi_delete_char_forward ],
		"vi-delete"               => [ \&vi_delete ],

	};

	$self->{"bindings"} = $bindings;
	$self->{"mappings"} = $mappings;
	return $self;
}

sub DESTROY {
	my $self = shift;
	$self->real_out("\n");
	ReadMode 0;
}

=pod

=item $sh->do_one_loop()

Does... one... loop. Makes a pass at grabbing input and processing it. For
speedy pasts, this loops until there are no characters left to read.
It will handle event processing, etc.

=cut

# Nonblocking readline
sub do_one_loop ($) { 
	my $self = shift;
	my $text;
	my $char;

	# Select for .01
	#
	if ($self->{"select"}->can_read(.01)) {
		my $bytes = sysread(STDIN, $text, 4096);
		for (my $i = 0; $i < length($text); $i++) {
			$char = substr($text,$i,1);
			$self->handle_key($char);
		}
	}
	
}

=pod

=item handle_key($key)

Handle a single character input. This is not a "key press" so much as doing all
the necessary things to handle key presses.

=cut

sub handle_key($$) {
	my $self = shift;
	my $char = shift;

	my $line = $self->{"input_line"} || "";
	my $pos = $self->{"input_position"} || 0;

	if (defined($self->{"input_slurper"})) {
		&{$self->{"input_slurper"}}($self, $char);
		return;
	}

	if ($self->{"escape"}) {
		$self->{"escape_string"} .= $char;
		if ($self->{"escape_expect_ansi"}) {
			$self->{"escape_expect_ansi"} = 0 if ($char =~ m/[a-zA-Z~]/);
		}

		$self->{"escape_expect_ansi"} = 1 if ($char eq '[');
		$self->{"escape"} = 0 unless ($self->{"escape_expect_ansi"});

		unless ($self->{"escape_expect_ansi"}) {
			my $estring = $self->{"escape_string"};

			$self->{"escape_string"} = undef;
			$self->execute_binding("\e".$estring);
		} else {
			return;
		}
	} elsif ($char eq "\e") {      # Trap escapes, they're speshul.
		if ($self->{"vi_mode"}) {
			if ($self->{"mode"} eq 'insert') {
				$self->{"input_position"}-- if ($self->{"input_position"} > 1);
				$self->{"mode"} = "command";
			}
		} else {
			$self->{"escape"} = 1;
			$self->{"escape_string"} = undef;
			return;
		}
	} elsif ((ord($char) < 32) || (ord($char) > 126)) {   # Control character
		$self->execute_binding($char);
	} elsif ((defined($char)) && (ord($char) >= 32)) {
		if (defined($self->{"mode"}) && $self->{"mode"} eq "command") {
			if ($char =~ m/[0-9]/) {
				$self->{"vi_count"} .= $char;
			} else {
				my $cmdwait = defined($self->{"vi_command_waiting"});

				$self->{"vi_count"} ||= 1;
				while ($self->{"vi_count"} > 0) {
					$self->execute_binding("vi_$char");
					$self->{"vi_count"}--;
				}
				if ($cmdwait) {
					&{$self->{"vi_command_waiting"}}($self, 1);
					$self->{"input_position"} = $self->{"vi_input_position"};
					delete $self->{"vi_command_waiting"};
				}
			}
		} else {
			if (defined($self->{"bindings"}->{"$char"})) {
				$self->execute_binding($char);
			} else  {
				# Insert the character in our string, wherever we are.
				#substr($line, $pos, 0) = $char;
				#$self->{"input_position"}++;
				$self->insert_at_cursor($char);
			}
		}

		# If we just did a tab completion, kill the state.
		delete($self->{"completion"}) if (defined($self->{"completion"}));
		$self->fix_inputline();
	}

	# This is sometimes a nice feature to have...
	# Press the any key!!!
	$self->{"lastchar"} = $char;
	$self->execute_binding("ANYKEY");

	#$self->fix_inputline();
}

=pod

=item execute_binding(raw_key)

Guess what this does? Ok I'll explain anyway... It takes a key and prettifies
it, then checks the known key bindings for a mapping and checks if that mapping
is a coderef (a function reference). If it is, it'll call that function. If
not, it'll do nothing. If it finds a binding for which there is no mapped
function, it'll tell you that it is an unimplemented function.

=cut

sub execute_binding ($$) {
	my $self = shift;
	my $str = shift;
	my $key = $self->prettify_key($str);

	#$self->out("Key: $key");

	my $bindings = $self->{"bindings"};
	my $mappings = $self->{"mappings"};

	if (defined($bindings->{$key})) {

		# Check if we have stored completion state and the next binding is
		# not complete-word. If it isn't, then kill the completion state.
		if (defined($self->{"completion"}) && $key ne 'ANYKEY' &&
			 $bindings->{$key} ne 'complete-word') {
			delete($self->{"completion"});
		}

		if (ref($mappings->{$bindings->{$key}}) =~ m/(CODE|ARRAY)/) {

			# This is a hack, passing $self instead of doing:
			# $self->function, becuase I don't want to do an eval.

			if ($1 eq 'ARRAY') {
				map { &{$_}($self) } @{$mappings->{$bindings->{$key}}};
			} else {
				&{$mappings->{$bindings->{$key}}}($self);
			}

		} else {
			$self->error("Unimplemented function, " . $bindings->{$key});
		}
	}
}

=pod

=item prettify_key(raw_key)

This happy function lets me turn raw input into something less ugly. It turns
control keys into their equivalent ^X form. It does some other things to turn
the key into something more readable 

=cut

sub prettify_key ($$) {
	my $self = shift;
	my $key = shift;

	# Return ^X for control characters, like CTRL+A...
	if (length($key) == 1) {   # One-character keycombos should only be ctrl keys
		if (ord($key) <= 26) {  # Control codes, another check anyway...
			return "^" . chr(65 + ord($key) - 1);
		}
		if (ord($key) == 127) { # Speshul backspace key
			return "^?";
		}
		if (ord($key) < 32) {
			return "^" . (split("", "\]_^"))[ord($key) - 28];
		}
	}

	# Return ESC-X for escape shenanigans, like ESC-W
	if (length($key) == 2) {
		my ($p, $k) = split("", $key);
		if ($p eq "\e") {    # This should always be an escape, but.. check anyway
			return "ESC-" . $k;
		}
	}

	# Ok, so it's not ^X or ESC-X, it's gotta be some ansi funk or a normal char.
	return $KEY_CONSTANTS{$key} || $key;
}

=pod 

=item real_out($string)

This function allows you to bypass any sort of evil shenanigans regarding output fudging. All this does is 'print @_;'

Don't use this unless you know what you're doing.

=cut

sub real_out {
	my $self = shift;
	print @_;
}

sub out ($;$) {
	my $self = shift;
	$self->real_out("\r\e[2K", @_, "\n");
	$self->fix_inputline();
}

sub error ($$) { 
	my $self = shift;
	$self->real_out("\r\e[2K");
	print STDERR "*> ", @_, "\n";
	$self->fix_inputline();
}

=pod 

=item fix_inputline

This super-happy function redraws the input line. If input_position is beyond the bounds of the terminal, it'll shuffle around so that it can display it. This function is called just about any time any key is hit.

=cut

sub fix_inputline ($) {
	my $self = shift;

	print "\r\e[2K";

	if ($self->{"echo"} == 0) {
		#print "Echo is off...\n";
		print $self->{"input_prompt"};
		return;
	}

	# If we're before the beginning of the terminal line, shuffle over!
	if ($self->{"input_position"} - $self->{"leftcol"} <= 0) {
		$self->{"leftcol"} -= 30;
		$self->{"leftcol"} = 0 if ($self->{"leftcol"} < 0);
	}

	# If we're past the end of the terminal line, shuffle back!
	# length = input_position - leftcol + input_prompt - leftcol
	my $pl = length($self->{"input_prompt"}) - $self->{"leftcol"};
	$pl = 0 if ($pl < 0);
	if ($self->{"input_position"} - $self->{"leftcol"} + $pl > $self->{"termcols"}) {
		$self->{"leftcol"} += 30;
	}

	# Can se show the whole line? If so, do it!
	if (length($self->{"input_line"}) + length($self->{"input_prompt"}) < $self->{"termcols"}) {
		$self->{"leftcol"} = 0;
	}

	# only print as much as we can in this one line.
	my $prompt = $self->{"input_prompt"};
	my $offset = 0;
	if ($self->{"leftcol"} <= length($self->{"input_prompt"})) {
		print substr($prompt,$self->{"leftcol"});
		$offset = length(substr($prompt,$self->{"leftcol"}));
	}

	print substr($self->{"input_line"}, $self->{"leftcol"}, $self->{"termcols"} - $offset);
	print "\r";
	print "\e[" . ($self->{"input_position"} - $self->{"leftcol"} + $offset) . 
	      "C" if (($self->{"input_position"} + $offset) > 0);
	STDOUT->flush();
}

sub newline {
	my $self = shift;
	# Process the input line.

	if ($self->{"supress_newline_echo"}) {
		# Clear the line
		$self->real_out("\e[2K");
	} else {
		$self->real_out("\n");
	}

	my $line = $self->{"input_line"};

	$self->{"input_line"} = "";
	$self->{"input_position"} = 0;
	$self->{"leftcol"} = 0;

	$self->callback("readline", $line);
	#if (ref($self->{"readline_callback"}) eq 'CODE') {
		#&{$self->{"readline_callback"}}($line);
	#}

	$self->fix_inputline();
}

sub kill_line {
	my $self = shift;

	# Ask for more data perhaps...
	$self->callback("fardelete");# if (length($self->{"input_line"}) == 0);

	$self->{"input_line"} = "";
	$self->{"input_position"} = 0;
	$self->{"leftcol"} = 0;

	#real_out("\r\e[2K");

	$self->fix_inputline();

	return 0;
}

sub forward_char {
	my $self = shift;
	if ($self->{"input_position"} < length($self->{"input_line"})) {
		$self->{"input_position"}++;
		$self->real_out("\e[C");
	}
}

sub backward_char {
	my $self = shift;
	if ($self->{"input_position"} > 0) {
		$self->{"input_position"}--;
		$self->real_out("\e[D");
	}
}

sub delete_char_backward {
	my $self = shift;

	$self->callback("fardelete") if (length($self->{"input_line"}) == 0);

	if ($self->{"input_position"} > 0) {
		substr($self->{"input_line"}, $self->{"input_position"} - 1, 1) = '';
		$self->{"input_position"}--;
		$self->fix_inputline();
	}
}

sub beginning_of_line {
	my $self = shift;
	$self->{"input_position"} = 0;
	$self->{"leftcol"} = 0;
	$self->fix_inputline();
}

sub end_of_line {
	my $self = shift;
	$self->{"input_position"} = length($self->{"input_line"});
	$self->fix_inputline();
}

sub delete_word_backward {
	my $self = shift;
	my $pos = $self->{"input_position"};
	my $line = $self->{"input_line"};
	#my $regex = '[A-Za-z0-9]';
	my $regex = '\S';
	my $bword;

	$self->callback("fardelete") if (length($self->{"input_line"}) == 0);
	$bword = $self->find_word_bound($line, $pos, WORD_BEGINNING | WORD_REGEX, $regex);

	#$self->error("Testing $bword $pos");
	# Delete whatever word we just found.
	substr($line, $bword, $pos - $bword) = '';

	# Update stuff...
	$self->{"input_line"} = $line;
	$self->{"input_position"} -= ($pos - $bword);

	$self->fix_inputline();
}

sub vi_backward_char {
	my $self = shift;

	$self->backward_char();
	$self->{"vi_done"} = 1;
}

sub vi_forward_char {
	my $self = shift;

	$self->forward_char();
	$self->{"vi_done"} = 1;
}

sub vi_forward_word {
	my $self = shift;
	my $pos = $self->{"input_position"};
	my $line = $self->{"input_line"};
	my $bword = $pos;
	my $BITS = WORD_NEXT;
	my $regex = shift;

	$BITS |= WORD_REGEX if (defined($regex)); 
	$bword = $self->find_word_bound($line, $pos, $BITS, $regex);

	$self->{"input_position"} = $bword;

	$self->{"vi_done"};
}

sub vi_forward_whole_word {
	my $self = shift;
	$self->vi_forward_word('\S');
	$self->{"vi_done"} = 1;
}

sub vi_beginning_word {
	my $self = shift;
	my $pos = $self->{"input_position"};
	my $line = $self->{"input_line"};
	my $bword = $pos;
	my $BITS = WORD_BEGINNING;
	my $regex = shift;

	$BITS |= WORD_REGEX if (defined($regex)); 
	$bword = $self->find_word_bound($line, $pos, $BITS, $regex);

	$self->{"input_position"} = $bword;

	$self->{"vi_done"};
}

sub vi_beginning_whole_word {
	my $self = shift;
	$self->vi_beginning_word('\S');
	$self->{"vi_done"} = 1;
}

sub vi_end_word {
	my $self = shift;
	my $pos = $self->{"input_position"};
	my $line = $self->{"input_line"};
	my $bword = $pos;
	my $BITS = WORD_END;
	my $regex = shift;

	$BITS |= WORD_REGEX if (defined($regex)); 
	$bword = $self->find_word_bound($line, $pos, $BITS, $regex);

	$self->{"input_position"} = $bword;

	$self->{"vi_done"};
}

sub vi_end_whole_word {
	my $self = shift;
	$self->vi_end_word('\S');
	$self->{"vi_done"} = 1;
}

sub vi_forward_charto {
	my $self = shift;

	# We need to wait for another character input...
	$self->{"jumpchardir"} = JUMP_CHARTO;
	$self->{"input_slurper"} = \&vi_jumpchar;
}

sub vi_forward_charat {
	my $self = shift;

	# We need to wait for another character input...
	$self->{"jumpchardir"} = JUMP_CHAR;
	$self->{"input_slurper"} = \&vi_jumpchar;
}

sub vi_backward_charto {
	my $self = shift;

	$self->{"jumpchardir"} = JUMP_BACKCHARTO;
	$self->{"input_slurper"} = \&vi_jumpchar;
}

sub vi_backward_charat {
	my $self = shift;

	$self->{"jumpchardir"} = JUMP_BACKCHAR;
	$self->{"input_slurper"} = \&vi_jumpchar;
}

sub vi_jumpchar {
	my $self = shift;
	my $char = shift;
	my $pos = $self->{"input_position"};
	my $line = $self->{"input_line"};
	my $newpos;
	my $mod = 0;

	delete $self->{"input_slurper"};

	$mod = ($self->{"jumpchardir"} & JUMP_CHARTO ? 1 : -1);

	if ($mod == 1) {
		#$self->out("F: $line / $pos / " . $line =~ m/^(.{$pos}[^$char]*)$char/);
		#$self->out("   " . " " x ($pos) . "^                   / $1");
		$pos = length($1) if (defined($1));
	} else {
		#$self->out("B: $line / $pos / " . $line =~ m/$char([^$char]*.{$pos})$/);
		#$self->out("   " . " " x ($pos - 1) . "^              / $1");
		$pos = length($line) - length($1) if (defined($1));
	}
	$self->{"input_position"} = $pos;

	$self->fix_inputline();
}

sub vi_bol {
	my $self = shift;
	$self->{"input_position"} = 0;
	$self->{"vi_done"} = 1;
}

sub vi_eol {
	my $self = shift;
	$self->{"input_position"} = length($self->{"input_line"});
	$self->{"vi_done"} = 1;
}
sub vi_insert {
	my $self = shift;

	$self->{"mode"} = "insert";
	$self->{"vi_done"} = 1;
}

sub vi_insert_at_bol {
	my $self = shift;

	$self->vi_bol();
	$self->vi_insert();
	$self->{"vi_done"} = 1;
}

sub vi_add {
	my $self = shift;

	$self->{"input_position"}++ if ($self->{"input_position"} < length($self->{"input_line"}));

	$self->vi_insert();
	$self->{"vi_done"} = 1;
}

sub vi_add_at_eol {
	my $self = shift;

	$self->vi_eol();
	$self->vi_add();
	$self->{"vi_done"} = 1;
}

sub vi_delete_char_forward {
	my $self = shift;
	unless ($self->{"input_position"} == 0) {
		substr($self->{"input_line"}, $self->{"input_position"} - 1, 1) = '';
		$self->{"input_position"}--;
	}
}

sub vi_delete_char_backward {
	my $self = shift;

	$self->callback("fardelete") if (length($self->{"input_line"}) == 0);

	substr($self->{"input_line"}, $self->{"input_position"}, 1) = '';
	$self->{"input_position"}-- if ($self->{"input_position"} == length($self->{"input_line"}) && $self->{"input_position"} > 0);
}

sub vi_delete {
	my $self = shift;
	my $exec = shift || 0;

	if ($exec == 1) {
		my ($start, $end);

		$self->callback("fardelete") if (length($self->{"input_line"}) == 0);

		if ($self->{"input_position"} < $self->{"vi_input_position"}) {
			$start = $self->{"input_position"};
			$end = $self->{"vi_input_position"};
		} else {
			$start = $self->{"vi_input_position"};
			$end = $self->{"input_position"};
		}
		substr($self->{"input_line"}, $start, ($end - $start)) = '';
	} else {
		# Mark such that we remember what command we're doing at the time
		# and set ourselves as the call back for the end of the next valid
		# command. soo.... something like:
		$self->{"vi_command_waiting"} = \&vi_delete;
		$self->{"vi_input_position"} = $self->{"input_position"};
	}
	
}

=pod

=item $sh->complete_word

This is called whenever the complete-word binding is triggered. See the
COMPLETION section below for how to write your own completion function.

=cut

sub complete_word {
	my $self = shift;
	my $pos = $self->{"input_position"};
	my $line = $self->{"input_line"};
	my $regex = "[A-Za-z0-9]";
	my $bword;
	my $complete;

	if (ref($self->{"completion_function"}) eq 'CODE') {
		my @matches;

	# Maintain some sort of state here if this is the first time we've 
	# hit complete_word() for this "scenario." What I mean is, we need to track
	# whether or not this user is hitting tab once or twice (or more) in the
	# same position.
RECHECK:
		if (!defined($self->{"completion"})) {
			$bword = $self->find_word_bound($line, $pos, WORD_BEGINNING | WORD_REGEX, '\S');
			$complete = substr($line,$bword,$pos - $bword);
			#$self->out("Complete: $complete");
			#$self->out(length($line) . " / $bword / $pos");

			# Make sure we can actually do this ?

			#$self->out("First time completing $complete");
			$self->{"completion"} = {
				"index" => 0,
				"original" => $complete,
				"pos" => $pos,
				"bword" => $bword,
				"line" => $line,
				"endpos" => $pos,
			};
		} else {
			$bword = $self->{"completion"}->{"bword"};
			#$self->out(length($line) . " / $bword / $pos");
			$complete = substr($line,$bword,$pos - $bword);
		}

		# If we don't have any matches to check against...
		unless (defined($self->{"completion"}->{"matches"})) {
			@matches = 
				&{$self->{"completion_function"}}($line, $bword, $pos, $complete);
			@{$self->{"completion"}->{"matches"}} = @matches;
		} else {
			@matches = @{$self->{"completion"}->{"matches"}};
		}

		my $match = $matches[$self->{"completion"}->{"index"}];

		return unless (defined($match));

		$self->{"completion"}->{"index"}++;
		$self->{"completion"}->{"index"} = 0 if ($self->{"completion"}->{"index"} == scalar(@matches));

		#$self->out(length($line) . " / $bword / $pos");
		substr($line, $bword, $pos - $bword) = $match . " ";

		$self->{"completion"}->{"endpos"} = $pos;

		$pos = $bword + length($match) + 1;
		$self->{"input_position"} = $pos;
		$self->{"input_line"} = $line;

		$self->fix_inputline();
	}
}

sub anykey {
	my $self = shift;

	$self->callback("anykey");
	#if (ref($self->{"anykey_callback"}) eq 'CODE') {
		#&{$self->{"anykey_callback"}};
	#}
}



#------------------------------------------------------------------------------
# Useful functions to set prompt and other things.

=pod

=item $sh->prompt([$prompt])

Get or set the prompt

=cut

sub prompt ($;$) {
	my $self = shift;

	if (@_) {
		$self->{"input_prompt"} = shift;
		$self->fix_inputline();
	}
	return $self->{"input_prompt"};
}

sub echo ($;$) {
	my $self = shift;

	if (@_) {
		$self->{"echo"} = shift;
	} 
	return $self->{"echo"};
}

# --------------------------------------------------------------------
# Helper functions
#

sub callback($$;$) {
	my $self = shift;
	my $callback = shift() . "_callback";
	if (ref($self->{$callback}) eq 'CODE') {
		$self->{$callback}->(@_);
	}
}

# Go from a position and find the beginning of the word we're on.
sub find_word_bound ($$$$;$) {
	my ($self, $line, $pos, $opts, $rx) = @_;
	my $nrx;
	$rx = '\\w' if (!($opts & WORD_REGEX));

	# Mod? This is either -1 or +1 depending on if we're looking behind or
	# if we're looking ahead.
	my $mod = ($opts & WORD_BEGINNING) ? -1 : 1;
	$nrx = qr/[^$rx]/;
	$rx = qr/[$rx]/;

	if ($opts & WORD_NEXT) {
		#$regex = qr/^.{$pos}(.+?)(?<!$regex)$regex/;
		$rx = qr/^.{$pos}(.+?)(?<!$rx)$rx/;
	} elsif ($opts & WORD_BEGINNING) {
		#$regex = qr/($regex+[^$regex]*)(?<=^.{$pos})/;
		$rx = qr/($rx+$nrx*)(?<=^.{$pos})/;
	} elsif ($opts & WORD_END) {
		#$regex = qr/^.{$pos}(.+?)$regex(?:[^$regex]|$)/;
		$rx = qr/^.{$pos}(.+?)$rx(?:$nrx|$)/;
	}

	#$self->out("$rx");

	if ($line =~ $rx) {
		$pos += length($1) * $mod;
	} else {
		$pos = ($mod == 1 ? length($line) : 0);
	}

	return $pos;
}

# -----------------------------------------------------------------------------
# Functions people might call on us...
#

sub insert_at_cursor($$) {
	my $self = shift;
	my $string = shift;

	substr($self->{"input_line"}, $self->{"input_position"}, 0) = $string;
	$self->{"input_position"} += length($string)
}

=pod

=back

=cut

1;
