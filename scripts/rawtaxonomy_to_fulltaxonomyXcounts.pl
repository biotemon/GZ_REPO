#!/usr/bin/perl
#This script takes a list of vague taxonomy terms (update taxonomy database --> mode 1) OR
#                  a list of vague taxonomy terms and their corresponding counts and experiment/treatment ID (update DB and write table --> mode 2) to 
#							(step 1) update taxonomy DB 
#							and to (step 2) generate a table of expanded taxonomy tags, counts per gene/feature, 
#							and experiment/treatment ID.

#Usage:
# ./rawtaxonomy_to_fulltaxonomyXcounts.pl mgrast_raw_counts.txt mode database_pathway

#The script does two steps, check and update the db (both modes), and (only mode 2) to prepare and print the taxonomyXcounts table.
#Requirements: - a fasta format RecA reference database (this is $reca_db). 
#              - a Taxonomy DB (this is $database)
#			   - the blastx (table tab format -outfmt 6) output file againts uniprot.

use DBI;
use strict;
use warnings;
use Term::ProgressBar;
use 5.010;
use List::MoreUtils qw(uniq);
use Data::Dumper qw(Dumper);

#SUBROUTINE TO CHECK SOMETHING IS IN AN ARRAY

sub in(&@){
  local $_;
  my $code = shift;
  for( @_ ){ # sets $_
    if( $code->() ){
      return 1;
    }
  }
  return 0;
}


#ASSUMPTION:
#Each blast file has only one (best) match per query sequence.

#--OPEN FILES--

my ($driver, $database, $dsn, $userid, $password, $dbh, $mode);

#Mode of action
$mode = $ARGV[1];

#GZ_db
use DBI;
$driver = "SQLite";
$database = $ARGV[2];
$dsn = "DBI:$driver:dbname=$database"; #No spaces here!!

$userid = "";
$password = "";
$dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
or die $DBI::errstr;

my(@reca_blast, %counts_of_id, $val, @fields, @fields1, @fields1A, $id);
my ($i, $cmd, $outcmd, $progress_bar, @fields2, $stmt, $species, @input_file);

#Open list file
open INPUT, $ARGV[0];
@input_file = <INPUT>;
close INPUT;

my (@row, @row1, @add_manually_terms);

print "Determining taxonomic query terms\n";
$progress_bar = Term::ProgressBar->new(scalar(@input_file));
$i = 0;

my($cmd3, $cmd4, $outcmd4, @fields3, $rsuperkingdom, $rkingdom, $rclass, $rorder, $rphylum, $rfamily, $rgenus, $rspecies, $itisid, @final_set, %taxid_of);
my(@unique_query_terms);
@unique_query_terms = ();

#Check for unique terms
for (my $i=0; $i < scalar(@input_file); $i++)
{
	chomp ($input_file[$i]);
	@fields = split "\t", $input_file[$i];
	$fields[0] =~ s/\(//g;
 	$fields[0] =~ s/\)//g;
 	$fields[0] =~ s/\[//g;
 	$fields[0] =~ s/\]//g;
	if(!(in { $fields[0] eq $_ } @unique_query_terms )){
		push @unique_query_terms, $fields[0];
	 }
	$progress_bar->update($i);
}

print "Updating taxonomy database and getting tax_ids\n";
$progress_bar = Term::ProgressBar->new(scalar(@unique_query_terms));

foreach my $id (@unique_query_terms)
{
 	$stmt = $dbh->prepare('SELECT * FROM TAXONOMY WHERE NO_RANK = ?');
	$stmt->execute($id) or die $DBI::errstr;
		
	@row1 = $stmt->fetchrow_array();

	if(scalar(@row1)>0){
	 	#We found taxonomy using the no_rank field
	 	$taxid_of{$id}=$row1[0];
	 	#print $id."\t".$row1[0]."\n";
	 }else{
	 	@fields2 = split ' ', $id;
	 	if(scalar(@fields2) > 1){
			#If the species start with sp. 
			if($fields2[1] eq 'sp.' || $fields2[1] eq 'sp' || $fields2[1] eq 'strain')
			{
				$stmt = $dbh->prepare('SELECT * FROM TAXONOMY WHERE GENUS = ?');
				$stmt->execute($fields2[0]) or die $DBI::errstr;
			}elsif($fields2[0] eq 'Candidatus'){
				$stmt = $dbh->prepare('SELECT * FROM TAXONOMY WHERE GENUS = ?');
				$stmt->execute($fields2[1]) or die $DBI::errstr;
			}else{
				$stmt = $dbh->prepare('SELECT * FROM TAXONOMY WHERE GENUS = ? AND SPECIES = ?');
				$stmt->execute($fields2[0], $fields2[1]) or die $DBI::errstr;
			}

		 	@row = $stmt->fetchrow_array();

		 	if(scalar(@row)>0){
		 		#We found taxonomy in the local DB matching species and genus
		 		$taxid_of{$id}=$row[0];
		 		#print $id."\t".$taxid_of{$id}."\n";
		 	}
		 }else{
			$stmt = $dbh->prepare('SELECT * FROM TAXONOMY WHERE GENUS = ?');
			$stmt->execute($fields2[1]) or die $DBI::errstr;
			@row = $stmt->fetchrow_array();

	 		if(scalar(@row)>0){
	 			#We found taxonomy in the local DB matching species and genus
	 			#print "\n";
	 			$taxid_of{$id}=$row[0];
	 			}
		 	}
		 	
		 if(exists $taxid_of{$id}){ 
		 	print '';
		 }
		 else{
		 	#### DOWNLOADING NEW TAXONOMY ENTRY #####
	 		$cmd3 = 'echo '.'\"'.$id.'\"'.'  > /Users/tito-admin/Tito/JOYELABACKUP/GZ_BACKUP/Temp14/get_taxonomy/query.txt';
	 		system($cmd3);
	 		$cmd4 =  'Rscript --vanilla /Users/tito-admin/Tito/JOYELABACKUP/GZ_BACKUP/Temp14/get_taxonomy/taxizeRscript.R /Users/tito-admin/Tito/JOYELABACKUP/GZ_BACKUP/Temp14/get_taxonomy/query.txt';
	 		$outcmd4 = `$cmd4`;
	 		@fields3 = split("\n", $outcmd4);
	 		foreach my $key (@fields3)
	 		{
	            	
	            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+kingdom\s+([0-9]+)/){
	                $rkingdom = $1;
	                $itisid = $2;
	            }
	            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+phylum\s+([0-9]+)/){
	                $rphylum= $1;
                    $itisid = $itisid.'.'.$2;
                }
	            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+class\s+([0-9]+)/){
	                $rclass= $1;
	                $itisid = $itisid.'.'.$2;
	            }
                if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+order\s+([0-9]+)/){
	                $rorder= $1;
	                $itisid = $itisid.'.'.$2;
	            }
                if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+family\s+([0-9]+)/){
	                $rfamily= $1;
	                $itisid = $itisid.'.'.$2;
	            }
                if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+genus\s+([0-9]+)/){
	                $rgenus= $1;
	                $itisid = $itisid.'.'.$2;
	            }
	            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+species\s+([0-9]+)/){
	                $rspecies= $1;
                    $itisid = $itisid.'.'.$2;
	            }
	        }
			#print $rkingdom."\t".$rphylum."\t".$rclass."\t".$rorder."\t".$rfamily."\t".$rgenus."\t".$rspecies."\t".$id."\n";
			if($rkingdom ne ''){
				#LOAD THIS IN THE DB
	            #Convert undef to blank values
	    		@final_set = ($itisid, $rkingdom, $rphylum, $rclass, $rorder, $rfamily, $rgenus, $rspecies, $id);
	    		for (my $z=0; $z < scalar(@final_set); $z++)
		   		{
		   			if(defined $final_set[$z]){
		   				print '';
		   			}else{
	    				$final_set[$z] = '';
	    			}
	    		}
	            $stmt = $dbh->prepare('INSERT INTO TAXONOMY VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
	            $stmt->execute(undef, "ITIS", $final_set[0], undef, $final_set[1], $final_set[2], $final_set[3], $final_set[4], $final_set[5], $final_set[6], $final_set[7] , '', $final_set[8]) or die "Couldn't execute statement: " . $stmt->errstr;
	                
	            #Request the taxid of the last inserted row
	            $stmt = $dbh->prepare('select seq from sqlite_sequence where name=?');
	            $stmt->execute("TAXONOMY");
	            my @row2 = $stmt->fetchrow_array();
	            $taxid_of{$id}=$row2[0];

	            #print "Added to DB from ITIS\n";	
				#print $final_set[0]."\t".$final_set[1]."\t".$final_set[2]."\t".$final_set[3]."\t".$final_set[4]."\t".$final_set[5]."\t".$final_set[6]."\t".$final_set[7]."\t".$final_set[8]."\n";

				$itisid = '';
	            $rkingdom = '';
	            $rphylum = '';
	            $rclass = '';
	            $rorder = '';
	            $rfamily = '';
	            $rgenus = '';
                $rspecies = '';
                @row2 = ();
			}else{
					$cmd3 = 'echo '.'\"'.$id.'\"'.'  > /Users/tito-admin/Tito/JOYELABACKUP/GZ_BACKUP/Temp14/get_taxonomy/query.txt';
	 				system($cmd3);
	               	$cmd4 =  'Rscript --vanilla /Users/tito-admin/Tito/JOYELABACKUP/GZ_BACKUP/Temp14/get_taxonomy/taxizeRscript.ncbi.R /Users/tito-admin/Tito/JOYELABACKUP/GZ_BACKUP/Temp14/get_taxonomy/query.txt';
		 			$outcmd4 = `$cmd4`;
		 			@fields3 = split("\n", $outcmd4);
		 			foreach my $key (@fields3)
			 		{
			           	if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+superkingdom\s+([0-9]+)/){
			                $rsuperkingdom = $1;
			                $itisid = $2;
		                }
		                if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+kingdom\s+([0-9]+)/){
			                $rkingdom = $1;
			                $itisid = $2;
		                }
			            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+phylum\s+([0-9]+)/){
			                $rphylum= $1;
			                $itisid = $itisid.'.'.$2;
		                }
		                if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+class\s+([0-9]+)/){
		                    $rclass= $1;
			                $itisid = $itisid.'.'.$2;
			            }
			            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+order\s+([0-9]+)/){
			                $rorder= $1;
		                    $itisid = $itisid.'.'.$2;
		                }
			           if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+family\s+([0-9]+)/){
			                $rfamily= $1;
			                $itisid = $itisid.'.'.$2;
			            }
			            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+genus\s+([0-9]+)/){
			                $rgenus= $1;
		                    $itisid = $itisid.'.'.$2;
		                }
			            if( $key =~ /[0-9]+\s+([a-zA-Z]+)\s+species\s+([0-9]+)/){
			                $rspecies= $1;
			                $itisid = $itisid.'.'.$2;
		                }
		            }
			        if(($rkingdom ne '') || ($rsuperkingdom ne '')){
			          	#LOAD THIS IN THE DB
			            #Convert undef to blank values
		    			@final_set = ($itisid, $rsuperkingdom, $rkingdom, $rphylum, $rclass, $rorder, $rfamily, $rgenus, $rspecies, $id);
			    		for (my $z=0; $z < scalar(@final_set); $z++)
			    		{
				    		if(defined $final_set[$z]){
				    			print '';
				    		}else{
				   				$final_set[$z] = '';
				   			}
			   			}
			            $stmt = $dbh->prepare('INSERT INTO TAXONOMY VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
			            $stmt->execute(undef, "NCBI", $final_set[0], $final_set[1], $final_set[2], $final_set[3], $final_set[4], $final_set[5], $final_set[6], $final_set[7] , $final_set[8], '', $final_set[9]) or die "Couldn't execute statement: " . $stmt->errstr;
			               	                
			           	#Request the taxid of the last inserted row
			            $stmt = $dbh->prepare('select seq from sqlite_sequence where name=?');
			            $stmt->execute("TAXONOMY");
		                my @row3 = $stmt->fetchrow_array();
		                $taxid_of{$id}=$row3[0];

		                #print "Added to DB from NCBI\n";	
						#print $final_set[0]."\t".$final_set[1]."\t".$final_set[2]."\t".$final_set[3]."\t".$final_set[4]."\t".$final_set[5]."\t".$final_set[6]."\t".$final_set[7]."\t".$final_set[8]."\t".$final_set[9]."\n";

			            $itisid = '';
			           	$rkingdom = '';
			            $rphylum = '';
			            $rclass = '';
		                $rorder = '';
		                $rfamily = '';
		                $rgenus = '';
			            $rspecies = '';
			            @row3 = ();
		           	}else{
		               	push @add_manually_terms, $id;
		            }

				}

		 }
	 }

	$i++;
	$progress_bar->update($i);

}

#Update some empty cells
$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Plantae", "Viridiplantae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Eukaryota", "Plantae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Eukaryota", "Animalia");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Archaea", "Archaea");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Bacteria", "Bacteria");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Eukaryota", "Animalia");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Eukaryota", "Chromista");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Eukaryota", "Protozoa");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET SUPERKINGDOM = ? WHERE KINGDOM = ?');
$stmt->execute("Eukaryota", "Fungi");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Streptophyta", "Magnoliopsida");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Ochrophyta", "Bacillariophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Ochrophyta", "Chrysophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Ochrophyta", "Phaeophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Ochrophyta", "Xanthophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Pyrrophycophyta", "Chloromonadophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Cryptophyta", "Cryptophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Myzozoa", "Dinophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Haptophyta", "Prymnesiophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET CLASS = ? WHERE FAMILY = ?');
$stmt->execute("Microsporidia", "Dubosqiidae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET ORDER_TAX = ? WHERE FAMILY = ?');
$stmt->execute("Microsporidia", "Dubosqiidae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE CLASS = ?');
$stmt->execute("Chromista", "Spirotrichea");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Ciliophora", "Spirotrichea");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE CLASS = ?');
$stmt->execute("Plantae", "Florideophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE CLASS = ?');
$stmt->execute("Rhodophyta", "Florideophyceae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE ORDER_TAX = ?');
$stmt->execute("Chromista", "Eustigmatales");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE ORDER_TAX = ?');
$stmt->execute("Ochrophyta", "Eustigmatales");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET CLASS = ? WHERE ORDER_TAX = ?');
$stmt->execute("Eustigmatophyceae", "Eustigmatales");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE ORDER_TAX = ?');
$stmt->execute("Chromista", "Dictyotales");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE ORDER_TAX = ?');
$stmt->execute("Ochrophyta", "Dictyotales");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET CLASS = ? WHERE ORDER_TAX = ?');
$stmt->execute("Phaeophyceae", "Dictyotales");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE ORDER_TAX = ?');
$stmt->execute("Excavata", "Cristamonadida");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE ORDER_TAX = ?');
$stmt->execute("Metamonada", "Cristamonadida");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET CLASS = ? WHERE ORDER_TAX = ?');
$stmt->execute("Parabasalia", "Cristamonadida");


$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE FAMILY = ?');
$stmt->execute("Protozoa", "Trypanosomatidae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE FAMILY = ?');
$stmt->execute("Euglenozoa", "Trypanosomatidae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET CLASS = ? WHERE FAMILY = ?');
$stmt->execute("Kinetoplastea", "Trypanosomatidae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET ORDER_TAX = ? WHERE FAMILY = ?');
$stmt->execute("Trypanosomatida", "Trypanosomatidae");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET KINGDOM = ? WHERE GENUS = ?');
$stmt->execute("Protozoa", "Ichthyobodo");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET PHYLUM = ? WHERE GENUS = ?');
$stmt->execute("Euglenozoa", "Ichthyobodo");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET CLASS = ? WHERE GENUS = ?');
$stmt->execute("Kinetoplastea", "Ichthyobodo");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET ORDER_TAX = ? WHERE GENUS = ?');
$stmt->execute("Prokinetoplastida", "Ichthyobodo");

$stmt = $dbh->prepare('UPDATE TAXONOMY SET FAMILY = ? WHERE GENUS = ?');
$stmt->execute("Prokinetoplastida", "Ichthyobodo");


if($mode == 2){
	#Processing final table
	print "Processing taxonomyXcounts table\n";
	$progress_bar = Term::ProgressBar->new(scalar(@input_file));

	my($cm4, $sample_id, $the_counts);
	$val = 'GENE_ID'.'$\'\t\''.'TAX_ID'.'$\'\t\''.'ASSEMBLY_ID'.'$\'\t\''.'READ_COUNTS'.'$\'\t\''.'SOURCE'.'$\'\t\''.'ITIS_NUMBER'.'$\'\t\''.'SUPERKINGDOM'.'$\'\t\''.'KINGDOM'.'$\'\t\''.'PHYLUM'.'$\'\t\''.'CLASS'.'$\'\t\''.'ORDER_TAX'.'$\'\t\''.'FAMILY'.'$\'\t\''.'GENUS'.'$\'\t\''.'SPECIES'.'$\'\t\''.'SUBSPECIES'.'$\'\t\''.'NO_RANK';
	$cmd4 = 'echo '.$val.'  > '.$ARGV[0].'_taxonomyXcounts.txt';
	system($cmd4);

	for (my $i=0; $i < scalar(@input_file); $i++)
	{
		chomp ($input_file[$i]);
		@fields = split "\t", $input_file[$i];
		$fields[0] =~ s/\(//g;
	 	$fields[0] =~ s/\)//g;
	 	$fields[0] =~ s/\[//g;
	 	$fields[0] =~ s/\]//g;

	 	$id = $fields[0];
	 	$sample_id = $fields[1];
	 	$the_counts = $fields[2];
	 	#print $id."\t".$taxid_of{$id}."\n";
	 	if(defined($taxid_of{$id})){
				$stmt = $dbh->prepare('SELECT * FROM TAXONOMY WHERE TAX_ID = ?');

				$stmt->execute($taxid_of{$id}) or die $DBI::errstr;
				@row = $stmt->fetchrow_array();

				for (my $z=0; $z < scalar(@row); $z++)
				    		{
					    		if(defined $row[$z]){
					    			print '';
					    		}else{
					   				$row[$z] = '';
					   			}
				   			}

				$val = $id.'$\'\t\''.$taxid_of{$id}.'$\'\t\''.$sample_id.'$\'\t\''.$the_counts.'$\'\t\''.$row[1].'$\'\t\''.$row[2].'$\'\t\''.$row[3].'$\'\t\''.$row[4].'$\'\t\''.$row[5].'$\'\t\''.$row[6].'$\'\t\''.$row[7].'$\'\t\''.$row[8].'$\'\t\''.$row[9].'$\'\t\''.$row[10].'$\'\t\''.$row[11].'$\'\t\''.$row[12];
				$cmd4 = 'echo '.$val.'  >> '.$ARGV[0].'_taxonomyXcounts.txt';
				system($cmd4);
		}else{
			$val = $id.'$\'\t\''.'NO_TAX_ID'.'$\'\t\''.$sample_id.'$\'\t\''.$the_counts.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.''.'$\'\t\''.'';
			$cmd4 = 'echo '.$val.'  >> '.$ARGV[0].'_taxonomyXcounts.txt';
			system($cmd4);
		}
		$progress_bar->update($i);

	 }
}


#PRINT VALUES TO BE ADDED MANUALLY IN THE DB 
my @unique_terms_to_add_in_db = uniq @add_manually_terms;
print "Processing add_manually_terms file\n";
foreach my $line (@unique_terms_to_add_in_db){
	$cmd4 = 'echo '.$line.'  >> '.$ARGV[0].'_add_manually_2_taxonomy_db.txt';
	system($cmd4);
}
