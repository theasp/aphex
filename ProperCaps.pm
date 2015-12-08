package ProperCaps;

use strict;

our @NoCapWords = qw(a an the is am are be will may was were to from with not on in by
		     or of has do out it are so on and over under by with near about above
		     around beneath beside but for after before off at as then than de);

our @ProperCapWords = ('II', 'III', 'IV', 'V', 'VI', 'VII', 'VII',
		       'IX', 'X', 'TV', 'DJ', 'MC', 'PM', 'PC', 'NDP',
		       'PEI', 'NS', 'CBC', 'EP', 'LP', 'CD', 'DVD',
		       'NOFX', 'PJ', 'REM', 'DiFranco', 'BBC', 'VNV');

sub properCap {
   my ($s) = @_;

   # Don't look here.  It's like, dirty laundry or sumpn.

   $s =~ s/(\b\S*\b)/\u$1/g;		# Fix words
   #$s =~ s/([\.,\-\[])([a-z]\S*\s?)/$1\u$2/g; # Do like this: "R.T.F.M. Cross-Eyed"
   $s =~ s/(?<=[\.,\-\[])(\w)/\u$1/g; # Do like this: "R.T.F.M. Cross-Eyed"
   $s =~ s/(\b[l,L]\')([a-z]*\b)/\u$1\u$2/g; # Do like this: L'America

   foreach my $word (@NoCapWords) { # Lower case some words.
      $s =~ s/([^\(:][\s,\-]+)\u$word(\s+[^\(:])/$1$word$2/gi; # Middle words only, and only if they don't come before or after a "(" or ":"
   }

   $s =~ s/([-,:\&\/\\\]])\s+([a-z])/$1 \u$2/g; # Do like this "- The Wonder"

   foreach my $word (@ProperCapWords) { # Words that should be a specific case
      $s =~ s/\b$word\b/$word/gi;	# Middle words only, and only if they don't come before or after a "(" or ":"
   }

   return $s;
}


1;
