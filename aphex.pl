#!/usr/bin/perl

use lib '/home/asp/projects/aphex/';
use open ':locale';

use utf8;
use Cwd;
use ProperCaps;
use YAML::Tiny;
use MP3::Tag;
#use XML::LibXML;
use File::Copy;
use File::Spec;
use File::Find;
use IO::File;
use IO::Dir;
use Getopt::Long qw(:config no_ignore_case gnu_getopt);
use Carp;
use Data::Dumper;
use Encode;
use strict;
use warnings;

#MP3::Tag->config(write_v24 => 1);


our $VER = '0.9.20';
our %DEFAULTCONFIG = (caseConvert=>'proper', # Case (none/lower/upper/proper)
                      lowerCaseFile=>0, # Lowercase the file name only
                      convertSpaces=>1,     # Don't convert spaces
                      test=>0,          # Testing mode
                      assumeYes=>0, # Ask before doing anything that could suck
                      writeId3v1=>1,
                      writeId3v2=>1,
                      wipeId3v2=>0,
                      updateId3=>0,
                      prefer=>'id3v2, id3v1, m3u, dir, file', # Order of preference for info
                      trackShift=>undef, # Shift the track number by this much
                      outFileFormat=>'%t - %B - %n',
                      inFileFormat=>undef,
                      outDirFormat=>'%b - %a',
                      inDirFormat=>undef,
                      recurse=>1,
                      remove=>undef,
                      m3uFile=>undef,
                      writeM3uFormat=>'00 - %b - %a',
                      writeM3u=>0,
                      inTheSwap=>1,
                      outTheSwap=>0,
                      renameDirs=>0,
                      doRenames=>1,
                      genMaxTracks=>1,
                      ignoreDiscTrackInfo=>0,
                      imageFormat=>'cover.jpg',
                      stripChars=>'/’',
                      replaceChars=>"_'",
                      workaroundVfat=>0,
                      trackNumSize=>2,
                      useConfig=>1,
                      forceComment=>"ID3 by Aphex $VER",
                      maxFileNameLength=>"128", # No option for it yet
                      swapTrackBand=>0,
                      stripDiscNumber=>0, # No option for it yet
                      forceAlbumFormat=>undef, # No option for it yet
                     );
our %PLUGINS;

our $DEBUG = 0;

our %RUNCONFIG;
GetOptions('case-convert=s'=>\$RUNCONFIG{caseConvert}, # +
 	   'lower-filename!'=>\$RUNCONFIG{lowerFilename}, # +
	   'convert-spaces!'=>\$RUNCONFIG{convertSpaces}, # +
	   'test!'=>\$RUNCONFIG{test}, # +
 	   'Y|assume-yes!'=>\$RUNCONFIG{assumeYes}, # +
 	   'write-id3v1!'=>\$RUNCONFIG{writeId3v1}, # +
 	   'write-id3v2!'=>\$RUNCONFIG{writeId3v2}, # +
 	   'wipe-id3v2!'=>\$RUNCONFIG{wipeId3v2}, # +
 	   'write-m3u-format=s'=>\$RUNCONFIG{writeM3uFormat}, # -
 	   'write-m3u!'=>\$RUNCONFIG{writeM3u}, # -
 	   'i|update-id3'=>\$RUNCONFIG{updateId3}, # +
 	   'p|prefer=s'=>\$RUNCONFIG{prefer}, # +
 	   'T|track-shift=i'=>\$RUNCONFIG{trackShift}, # +
 	   'out-file-format=s'=>\$RUNCONFIG{outFileFormat}, # +
 	   'in-file-format=s'=>\$RUNCONFIG{inFileFormat}, # +
	   'out-dir-format=s'=>\$RUNCONFIG{outDirFormat}, # +
 	   'in-dir-format=s'=>\$RUNCONFIG{inDirFormat}, # +
 	   'R|remove=s'=>\$RUNCONFIG{remove}, # +
 	   'r|recurse!'=>\$RUNCONFIG{recurse}, # +
           '3|m3u=s'=>\$RUNCONFIG{m3uFile}, # +
 	   'in-the-swap!'=>\$RUNCONFIG{inTheSwap}, # +
 	   'out-the-swap!'=>\$RUNCONFIG{outTheSwap}, # +
 	   'rename-dirs!'=>\$RUNCONFIG{renameDirs}, # +
 	   'do-renames!'=>\$RUNCONFIG{doRenames}, # +
 	   'M|gen-maxtracks!'=>\$RUNCONFIG{genMaxTracks}, # +
           'ignore-disc-track-info!'=>\$RUNCONFIG{ignoreDiscTrackInfo},
	   'image-format=s'=>\$RUNCONFIG{imageFormat}, # +
	   'a|album=s'=>\$RUNCONFIG{forceAlbum}, # +
	   't|track=i'=>\$RUNCONFIG{forceTrack}, # +
	   'm|maxtracks=i'=>\$RUNCONFIG{forceMaxtracks}, # +
	   'b|band=s'=>\$RUNCONFIG{forceBand}, # +
	   'B|track-band=s'=>\$RUNCONFIG{forceTrackBand}, # +
 	   'n|name=s'=>\$RUNCONFIG{forceName}, # +
 	   'g|genre=s'=>\$RUNCONFIG{forceGenre}, # +
 	   'y|year=i'=>\$RUNCONFIG{forceYear}, # +
 	   'c|comment=s'=>\$RUNCONFIG{forceComment}, # +
 	   'd|debug+'=>\$DEBUG, # +
 	   'S|strip-chars=s'=>\$RUNCONFIG{stripChars}, # +
 	   'replace-chars=s'=>\$RUNCONFIG{replaceChars}, # +
 	   'workaround-vfat!'=>\$RUNCONFIG{workaroundVfat}, # +
           'track-num-size=i'=>\$RUNCONFIG{trackNumSize},
           'use-config!'=>\$RUNCONFIG{useConfig},
           'swap-track-band!'=>\$RUNCONFIG{swapTrackBand},
           'strip-disc-number!'=>\$RUNCONFIG{stripDiscNumber},
           'album-format=s'=>\$RUNCONFIG{forceAlbumFormat},
	  ) || exit 1;

our %defaultFormats = (file=>['%B[ _]-[ _]%a[ _]-[ _]%t[ _]-[ _]%n',
                              '%B[ _]-[ _]%a[ _]-[ _]\s*\(%t\)%n',
                              '%t[ _]-[ _]%B[ _]-[ _]%n',
                              '%B[ _]-[ _]%t[ _]-[ _]%n',
                              '%t[ _]-[ _]%n',
                              '%B[ _]-[ _]%n',
                              '%B-%a-%t-%n',
                              '%B-%a-\s*\(%t\)%n',
                              '%t-%b-%n',
                              '%B-%t-%n',
                              '%t-%n',
                              '%t\.%n',
                              '%t[ _]%n',
                              '%B-%n',
                              '%n'],
                       dir=>['.*/\(%y\) %b - %a',
                             '.*/%b - %a \(%y\)',
                             '.*/%b - %a',
                             '.*/%b-%a\s*\(%y\)',
                             '.*/%b-%a']
                      );

our %formatDefs = ('t'=>{field=>'track', re=>'\s*(\d+)\s*', out=>'%02d'},
		   'a'=>{field=>'album', re=>'\s*([^/]*?)\s*', out=>'%s'},
		   'b'=>{field=>'band', re=>'\s*([^/]*?)\s*', out=>'%s'},
		   'B'=>{field=>'trackBand', re=>'\s*([^/]*?)\s*', out=>'%s'},
		   'n'=>{field=>'name', re=>'\s*([^/]*?)\s*', out=>'%s'},
		   'y'=>{field=>'year', re=>'\s*(\d\d\d\d)\s*', out=>'%04d'},
		   'c'=>{field=>'comment', re=>'\s*([^/]*?)\s*', out=>'%s'},
		   'g'=>{field=>'genre', re=>'\s*([^/]*?)\s*', out=>'%s'},
		   'm'=>{field=>'maxTracks', re=>'\s*(\d+)\s*', out=>'%02d'},
		   '%'=>{field=>undef, re=>undef, out=>'%'});

our $CONFIG = {};

buildConfig($CONFIG, '.');

$formatDefs{'t'}->{out} = "%0" . $CONFIG->{trackNumSize} . "d";

our $m3uTracks;
$m3uTracks = readM3u($CONFIG->{m3uFile}) if defined($CONFIG->{m3uFile});

my @files;
foreach my $file (@ARGV) {
   #utf8::upgrade($file);

   if (-d $file) {
      if ($CONFIG->{recurse}) {
	 my %dirs;
	 find({no_chdir=>1,
	       wanted=>sub {push(@{$dirs{$1}}, decode_utf8($_)) if -f $_ && $_ =~ /^(.*)\/.*\.mp3$/i;},
	      }, $file);


	 foreach my $dir (sort(keys(%dirs))) {
            # Nonsense with utf decode and upgrade is to work around
            # stupidness.
            utf8::upgrade($dir);
            buildConfig($CONFIG, $dir);
	    mainLoop(sort(@{$dirs{$dir}}));
	 }

      } else {
	 error("Can't process directory, recurse is off");
      }
   } else {
      push(@files, $file);
   }
}

mainLoop(@files);

sub mainLoop {
   my (@files) = @_;

   return undef if $#files == -1;

   my @process;
   foreach my $file (@files) {
      print "$file\n";
      push(@process, processFile($file));
   }

   my %dirInfo;
   my $maxTracks = 0;
   foreach my $fileInfo (@process) {
      my $curMaxTracks = $fileInfo->{info}->{track};
      $maxTracks = $curMaxTracks if defined($curMaxTracks) && $curMaxTracks ne ''
	&& $maxTracks < int($curMaxTracks);

      my ($vol, $dir, undef) = File::Spec->splitpath($fileInfo->{origFile});
      push(@{$dirInfo{File::Spec->catfile($vol, $dir)}}, $fileInfo->{info});
   }

   if ($CONFIG->{genMaxTracks} && $maxTracks != 0) {
      foreach my $fileInfo (@process) {
	 $fileInfo->{info}->{maxTracks} = $maxTracks;
      }
   }

   debug("Files to process: " . ($#process+1));

   doTagFiles(\@process) if $CONFIG->{updateId3};
   doRenameFiles(\@process) if $CONFIG->{doRenames};
}


sub processFile {
   my ($origFile) = @_;
   debug("Examining file $origFile");

   $origFile = File::Spec->rel2abs($origFile);

   my ($volume, $dirs, $origFileName) = File::Spec->splitpath($origFile);

   my $name = $origFileName;

   $name =~ s/$CONFIG->{remove}// if defined($CONFIG->{remove});

   $name =~ s/\.([^\.]+)$//;
   my $ext = $1 || "mp3";

   $dirs =~ s/\/$//;

   my %sources;

   $sources{m3u}->{track} = $m3uTracks->{$origFile} if defined($m3uTracks->{$origFile});
   $sources{file} = parseStringFormats($name, $CONFIG->{formats}->{compiled}->{file});
   $sources{dir} = parseStringFormats($dirs, $CONFIG->{formats}->{compiled}->{dir});

   my $mp3 = new MP3::Tag($origFile) || error("Can't read ID3 tag from file: " . $origFile . ": $!");
   $mp3->getTags();

   $sources{id3v1} = readId3v1($mp3->{ID3v1}) if exists($mp3->{ID3v1});
   $sources{id3v2} = readId3v2($mp3->{ID3v2}) if exists($mp3->{ID3v2});

   my %info;
   foreach my $source (split(/[\, ]+/, $CONFIG->{prefer})) { #broken cperl mode /)) {
      if (defined($sources{$source})) {
	 foreach my $key (keys(%{$sources{$source}})) {
	    $info{$key} = $sources{$source}->{$key} unless defined $info{$key};
	 }
      }
   }

   foreach ('band', 'trackBand', 'album', 'name') {
      if (defined($info{$_})) {
	 $info{$_} = "The " . $info{$_} if $CONFIG->{inTheSwap} && $info{$_} =~ s/, the$//i;
	 $info{$_} .= ", The" if $CONFIG->{outTheSwap} && $info{$_} =~ s/^the //i;

	 $info{$_} = fixChunk($info{$_});
      }
   }


   foreach ('band', 'trackBand', 'album', 'name', 'genre', 'comment', 'track', 'year') {
      $info{$_} = '' unless defined($info{$_});
      utf8::upgrade($info{$_});
   }

   # Merge these
   $info{band} = $info{trackBand} if $info{band} eq '';
   $info{trackBand} = $info{band} if $info{trackBand} eq '';

   if ($CONFIG->{swapTrackBand}) {
      my $tmp = $info{band};
      $info{band} = $info{trackBand};
      $info{trackBand} = $tmp;
   }

   my %forceMap = (forceAlbum => "album",
                   forceTrack => "track",
                   forceMaxtracks => "maxtracks",
                   forceBand => "band",
                   forceTrackBand => "trackBand",
                   forceName => "name",
                   forceGenre => "genre",
                   forceYear => "year",
                   forceComment => "comment");

   foreach my $key (keys(%forceMap)) {
      $info{$forceMap{$key}} = $CONFIG->{$key} if defined($CONFIG->{$key}) && $CONFIG->{$key} ne '';
   }

   $info{track} += $CONFIG->{trackShift} if defined($CONFIG->{trackShift}) && defined($info{track}) && $info{track} ne '';
   $info{name} = $CONFIG->{"forceName-$info{track}"} if defined($CONFIG->{"forceName-$info{track}"});

   if (defined($CONFIG->{forceAlbumFormat})) {
      $info{album} = fillStringFormat($CONFIG->{forceAlbumFormat}, \%info);
   }

   my $fileInfo = {};

   if (defined($CONFIG->{stripChars}) && $CONFIG->{stripChars} ne '') {
      foreach my $key (keys(%info)) {
         $fileInfo->{$key} = $info{$key};

         my $from = $CONFIG->{stripChars};
         my $to = $CONFIG->{replaceChars};

         my $len = length($from);

         for (my $pos = 0; $pos <= $len; $pos++) {
            my $c = substr($from, $pos, 1);
            my $t = substr($to, $pos, 1);

            $fileInfo->{$key} =~ s/$c/$t/g;
         }
      }
   } else {
      $fileInfo = \%info;
   }

   debug(Dumper($fileInfo));

   my $newFileName = buildNewFileName($CONFIG->{outFileFormat}, $fileInfo);

   if (length($newFileName) > $CONFIG->{maxFileNameLength} + 1 + length($ext)) {
      debug("Trimming long filename");
      $newFileName = substr($newFileName, 0, $CONFIG->{maxFileNameLength} - 1 - length($ext));
   }

   $newFileName .= '.' . $ext;



   my $newDirs = $dirs;
   $newDirs = buildNewDirs($CONFIG->{outDirFormat}, $dirs, $fileInfo) if $CONFIG->{renameDirs};

   my $newFile = File::Spec->catpath($volume, $newDirs, $newFileName);

   return {origFile=>$origFile,
	   newFile=>$newFile,
	   info=>\%info};
}


sub doTagFiles {
   my ($process) = @_;

   foreach my $fileInfo (@{$process}) {
      print "\n" . $fileInfo->{origFile} . "\n";
      printInfo($fileInfo->{info});
   }

   if (! $CONFIG->{test}){ 
      if (! $CONFIG->{assumeYes}) {
	 print 'Tag files? ';

	 $_ = <STDIN>;
	 return if !defined($_) || ! /^y/i;
      }

      foreach my $fileInfo (@{$process}) {
	 debug('Processing tag for file: ' . $fileInfo->{origFile});

	 my $mp3 = new MP3::Tag($fileInfo->{origFile}) || error("Can't read ID3 tag from file: $fileInfo->{origFile}: $!");
	 $mp3->getTags();

	 my $tag = $mp3->{ID3v1} || $mp3->new_tag('ID3v1');

         if ($CONFIG->{writeId3v1}) {
            debug("Writing ID3v1...");
            writeId3v1($tag, $fileInfo->{info});
            debug("Done.");
         }

         $tag = $mp3->{ID3v2};

	 if (defined($tag) && $CONFIG->{wipeId3v2}) {
	    debug("Wiping ID3v2...");
	    $tag->remove_tag();
	    $tag = undef;

	    # Not sure if this is necessary
	    $mp3 = new MP3::Tag($fileInfo->{origFile}) || error("Can't read ID3 tag from file: $fileInfo->{origFile}: $!");
	    $mp3->getTags();
	    debug("Done.");
	 }

         if ($CONFIG->{writeId3v2}) {
           if (! defined($tag)) {
              $tag = $mp3->new_tag('ID3v2') || croak("Can't create ID3v2 tag, something is very wrong");
           }

           debug("Writing ID3v2...");
           writeId3v2($tag, $fileInfo->{info});
           debug("Done.");
        }
      }
   }
}


sub doRenameFiles {
   my ($process) = @_;

   my @renames;

   my %dirRenames;

   foreach my $fileInfo (@{$process}) {
      if (File::Spec->abs2rel($fileInfo->{origFile}) ne File::Spec->abs2rel($fileInfo->{newFile})) {
	 my $from = $fileInfo->{origFile};
	 my $to = $fileInfo->{newFile};

	 my ($fromVol, $fromDirs, $fromFile) = File::Spec->splitpath($from);
	 my ($toVol, $toDirs, $toFile) = File::Spec->splitpath($to);

	 $to = File::Spec->catpath($fromVol, $fromDirs, $toFile);

	 my $fromDir = File::Spec->catpath($fromVol, $fromDirs, undef);
	 my $toDir = File::Spec->catpath($toVol, $toDirs, undef);
	 $fromDir =~ s/\/$//;
	 $toDir =~ s/\/$//;

	 $dirRenames{$fromDir} = $toDir if $fromDir ne $toDir;

	 push(@renames, {from=>$from, to=>$to});

         utf8::decode($from);
         utf8::decode($to);

	 printf("Rename: %s -> %s\n",
		File::Spec->abs2rel($from),
		File::Spec->abs2rel($to));
      }
   }

   foreach my $from (keys(%dirRenames)) {
      printf("Dir Rename: %s -> %s\n",
	     File::Spec->abs2rel($from) || '.',
	     File::Spec->abs2rel($dirRenames{$from}));
   }

   if (! $CONFIG->{test} && $#renames != -1) {
      if (! $CONFIG->{assumeYes}) {
	 print "Rename files? ";

	 $_ = <STDIN>;
	 return if ! /^y/i;
      }

      foreach my $ren (@renames) {
	 move($ren->{from}, $ren->{to}) || croak("Can't rename $ren->{from} to $ren->{to}: $!");
      }

      foreach (sort {length($b) <=> length($a)} (keys(%dirRenames))) {
	 my $from = $_; # Incase we change dirs

	 if ($CONFIG->{workaroundVfat}) {
	    if (lc($_) eq lc($dirRenames{$_})) {
	       my $to = ".aphex-$$";
	       $to =~ s/\/$//;

	       move($_, $to) || croak("Can't rename $_ to $to: $!");
	       $from = $to;
	    }
	 }

	 if (-d $dirRenames{$_}) {
	    my $dh = new IO::Dir($from) || croak("Can't open dir: $_: $!");
	    while (defined(my $origFile = $dh->read())) {
	       next if $origFile =~ /^\.\.?$/;

	       move("$from/$origFile", "$dirRenames{$_}/$origFile") || croak("Can't rename $from/$origFile to $dirRenames{$_}/: $!");
	    }
            if (-d $from) {
               rmdir($from) || croak("Can't rmdir $from: $!");
            }
	 } else {
	     my ($vol, $dir) = File::Spec->splitpath($dirRenames{$_}, 1);
	     my @makeDirs = File::Spec->splitdir($dir);

	     for (my $i = 0; $i < $#makeDirs; $i++) {
		 my $dir = File::Spec->catpath($vol, File::Spec->catdir(@makeDirs[0..$i]));
		 if (! -d $dir) {
		     mkdir($dir) || croak("Can't mkdir $dir: $!");
		 }
	     }

	     move($from, $dirRenames{$_}) || croak("Can't rename $from to $dirRenames{$_}: $!");
	 }
      }
   }
}


sub printInfo {
   my ($info) = @_;

   my $track = $info->{track};
   $track .= '/' . $info->{maxTracks} if defined($info->{maxTracks});

   printf("Track: %-8s\tName: %s\n", $track, $info->{name});
   printf("Genre: %-8s\tBand: %s\n", $info->{genre}, ($info->{trackBand} eq $info->{band} ? $info->{band} : fillStringFormat("%b (%B)", $info)));
   printf("Year: %-9s\tAlbum: %s\n", $info->{year}, $info->{album});
   printf("Comment: %s\n", $info->{comment}) if defined($info->{comment}) && ! ref($info->{comment});
}


sub buildNewFileName {
   my ($format, $info) = @_;

   $format = fillStringFormat($format, $info);

   $format = lc($format) if $CONFIG->{lowerFilename};

   return $format;
}


sub buildNewDirs {
   my ($format, $dirs, $info) = @_;

   $format = fillStringFormat($format, $info);

   $format = lc($format) if $CONFIG->{lowerFilename};

   my @inDirs = File::Spec->splitdir($dirs);
   my @outDirs = File::Spec->splitdir($format);

   $format = join('/', @inDirs[0..($#inDirs-$#outDirs-1)], @outDirs);

   return $format;
}


sub fillStringFormat {
   my ($format, $info) = @_;

   my $inField = undef;
   my $len = length($format);

   for (my $pos = 0; $pos <= $len; $pos++) {
      my $c = substr($format, $pos, 1);

      if (defined($inField)) {
	 if (defined($formatDefs{$c})) {
	    my $string = undef;

	    if (defined($formatDefs{$c}->{field})) {
	       $string = $info->{$formatDefs{$c}->{field}};

	       $string = fixChunk($string . ', The') if $string =~ s/^the //i;

	       error("Missing required attribute: " . $formatDefs{lc($c)}->{field} . "\n" . Dumper(format=>$format, info=>$info))
		 if ! defined($string) || $string eq '';
	    } else {
	       $string = $formatDefs{$c}->{re};
	    }

	    if (defined($string)) {
	       $string = sprintf($formatDefs{$c}->{out}, $string);
	       substr($format, $pos-1, 2) = $string;
	       $pos += length($string)-1;
	       $len = length($format);
	    }
	 } 
	 $inField = undef;
      } else {
	 $inField = 1 if $c eq '%';
      }
   }
   return $format;
}


sub parseStringFormats {
   my ($string, $compiledFormats) = @_;

   my %fieldData;

   foreach my $fmt (@{$compiledFormats}) {
      my $re = $fmt->{re};
      my $fields = $fmt->{fields};

      debug("Applying $re on $string");

      if ($string =~ /$re/) {
	 print "Match: " if $DEBUG;
	 foreach my $fieldNum (0..$#{$fields}) {
	    print $fields->[$fieldNum] if $DEBUG;
	    $fieldData{$fields->[$fieldNum]} = eval('$' . ($fieldNum+1));
	 } continue {
	    print ', ' if $DEBUG && $fieldNum != $#{$fields};
	 }
	 print "\n" if $DEBUG;

	 last;
      }
   }

   return \%fieldData;
}


sub compileFormatRes {
   my ($formats) = @_;

   my @compiledFormats;

   foreach my $pat (@{$formats}) {
      my ($re, $fields) = buildReFromPat($pat);

      push(@compiledFormats, {re=>$re,
			      fields=>$fields});
   }

   return \@compiledFormats;
}


sub buildReFromPat {
   my ($pat) = @_;

   my @fields;

   my $inField = undef;
   my $len = length($pat);
   for (my $pos = 0; $pos <= $len; $pos++) {
      my $c = substr($pat, $pos, 1);
      if (defined($inField)) {
	 my $out = $formatDefs{$c}->{re};
	 $out = $formatDefs{$c}->{out} unless defined($out);

	 substr($pat, $pos-1, 2) = $out;
	 $pos += length($out)-1;
	 $len = length($pat);

	 push(@fields, $formatDefs{$c}->{field}) if defined($formatDefs{$c}->{field});

	 $inField = undef;
      } else {
	 $inField = 1 if $c eq '%';
      }
   }

   return(qr/^$pat$/i, \@fields);
}


sub fixChunk {
   my ($s) = @_;

   if ($CONFIG->{convertSpaces}) { # Convert stuff to spaces
      $s =~ s/_/ /g;
      $s =~ s/%20/ /g;
   }

   $s =~ s/^\s*//;
   $s =~ s/\s*$//;


   if ($CONFIG->{caseConvert} eq 'lower') {
      $s = lc($s);
   } elsif ($CONFIG->{caseConvert} eq 'upper') {
      $s = uc($s);
   } elsif ($CONFIG->{caseConvert} eq 'proper') {
      $s = ProperCaps::properCap(lc($s));
   } elsif ($CONFIG->{caseConvert} eq 'none') {
   } else {
      error('Invalid value for case-convert: ' . $CONFIG->{caseConvert});
   }

   return $s;
}


sub writeId3v1 {
   my ($tag, $info) = @_;

   $tag->song($info->{name});
   $tag->artist($info->{band});
   $tag->album($info->{album});
   $tag->comment($info->{comment});
   $tag->year($info->{year});
   $tag->genre($info->{genre});

   my $track = $info->{track};
#   $track .= '/' . $info->{maxTracks} if defined($info->{maxTracks});
   $tag->track($track);

   $tag->writeTag();
}


sub writeId3v2 {
   my ($tag, $info) = @_;

   my $curFrames = $tag->getFrameIDs();

   $tag->frame_select_by_descr("TPE1", $info->{trackBand});
   $tag->frame_select_by_descr("TPE2", $info->{band});

   $tag->song($info->{name});
   $tag->album($info->{album});
   $tag->comment($info->{comment});
   $tag->year($info->{year});
   $tag->genre($info->{genre});

   my $track = $info->{track};
   $track .= '/' . $info->{maxTracks} if defined($info->{maxTracks});

   $tag->track($track);
   # editId3v2Frame($tag, $curFrames, 'TRCK', $track);

   my ($commentFrame) = $tag->getFrame('COMM');
   if (!defined($commentFrame)) {
      $commentFrame = {};
   }

   if ($CONFIG->{stripDiscNumber}) {
      $tag->frame_select_by_descr("TPOS", undef);
   }

   $commentFrame->{Text} = $info->{comment};
   editId3v2Frame($tag, $curFrames, 'COMM', 'ENG', 'Comment', $info->{comment});

   $tag->write_tag();
}


sub editId3v2Frame {
   my ($tag, $curFrames, $frame, @data) = @_;

   if (defined($curFrames->{$frame})) {
      $tag->change_frame($frame, @data);
   } else {
      $tag->add_frame($frame, @data) || croak("Can't add frame $frame with: " . Dumper(\@data));
   }
}


sub readId3v1 {
   my ($tag) = @_;

   my %info;

   $info{name} = $tag->song();
   $info{band} = $tag->artist();
   $info{album} = $tag->album();
   $info{comment} = $tag->comment();
   $info{year} = $tag->year();
   $info{genre} = $tag->genre();

   if (! $CONFIG->{ignoreDiscTrackInfo}) {
      $info{track} = $tag->track();
      $info{maxTracks} = $1 if defined($info{track}) && $info{track} =~ s/\/(\d+)$//;
   }

   return \%info;
}


sub readId3v2 {
   my ($tag) = @_;

   my %info;

   $info{name} = $tag->song();

   if (! $CONFIG->{ignoreDiscTrackInfo}) {
      $info{track} = $tag->track();
      $info{maxTracks} = $1 if defined($info{track}) && $info{track} =~ s/\/(\d+)$//;
   }

   $info{band} = $tag->frame_select_by_descr('TPE2');
   $info{trackBand} = $tag->frame_select_by_descr('TPE1');
   $info{album} = $tag->album();

   debug("Is UTF8? " . utf8::is_utf8($info{album}));

   $info{genre} = $tag->genre();

   ($info{comment}) = $tag->getFrame('COMM');

   $info{comment} = $info{comment}->{Text} if defined($info{comment}) && ref($info{comment});

   ($info{year}) = $tag->getFrame('TORY');

   # NEED TO DECODE THIS
   #($info{genre}) = $tag->getFrame('TCON');

   return \%info;
}


sub readM3u {
   my ($file) = @_;

   my ($m3uVol, $m3uDirs, $m3uFile) = File::Spec->splitpath(File::Spec->rel2abs($file));

   my $fh = new IO::File($file, 'r') || error("Can't open M3U File: $file: $!");

   my $c = 1;
   my %tracks;

   while (<$fh>) {
      chomp();
      s/#.*$//;
      s/^\s+//;
      s/\s+$//;

      next if $_ eq '';

      $_ = File::Spec->catpath($m3uVol, $m3uDirs, $_) if ! File::Spec->file_name_is_absolute($_);  	

      $tracks{$_} = $c++ if $_ ne '';
   }

   $fh->close();

   return \%tracks;
}


sub buildConfig {
   my ($config, $startDir) = @_;

   # Clear the config
   %{$config} = ();

   debug("Building Config");
   mergeHash($config, \%DEFAULTCONFIG);
   mergeHash($config, \%RUNCONFIG);

   if (defined ($startDir) && $config->{useConfig}) {
      debug("Looking for config files");
      $startDir = Cwd::abs_path($startDir);
      my $prev = '';
      foreach my $dir (File::Spec->splitdir($startDir)) {
         $dir = File::Spec->catdir($prev, $dir);

         my $configFile = File::Spec->catfile($dir, '.aphex.yaml');
         debug("Looking for $configFile");
         readConfig($config, $configFile) if -e $configFile;
         $prev = $dir;
      }
   }

   mergeHash($config, \%RUNCONFIG);

   if (defined($config->{stripChars}) && defined($config->{replaceChars})) {
      if (length($config->{stripChars}) != length($config->{replaceChars})) {
         error("strip-chars and replace-chars must be the same length");
      }
   }

   $config->{formats}->{file} = [$config->{inFileFormat}] if defined($CONFIG->{inFileFormat});
   $config->{formats}->{dir} = [$config->{inDirFormat}] if defined($CONFIG->{inDirFormat});

   push(@{$config->{formats}->{file}}, @{$defaultFormats{file}});
   push(@{$config->{formats}->{dir}}, @{$defaultFormats{dir}});

   foreach my $key (keys(%{$config->{formats}})) {
      $config->{formats}->{compiled}->{$key} = compileFormatRes($config->{formats}->{$key});
   }
}


sub readConfig {
   my ($config, $file) = @_;

   debug("Reading config: $file");

   my $yaml = YAML::Tiny->read($file) || error("Unable to read config file: $file: " . YAML::Tiny->errstr());

   mergeHash($config, $yaml->[0]);
}


sub mergeHash {
   my ($outHash, @hashes) = @_;

   foreach my $curHash (@hashes) {
      foreach my $key (keys(%{$curHash})) {
         if (defined($curHash->{$key})) {
            debug("Setting $key to $curHash->{$key}");
            $outHash->{$key} = $curHash->{$key};
         }
      }
   }
}


sub error {
   my ($s) = @_;
   print STDERR "ERROR: $s\n";
   exit 1;
}


sub debug {
   my ($s) = @_;
   print STDERR "DEBUG: $s\n" if $DEBUG;
}
