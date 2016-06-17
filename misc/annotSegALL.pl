#!/packages/perl/5.14.2/bin/perl
###!/usr/bin/perl 
## Converts the SEG file from DNAcopy to a gVCF format and annotates each segment with Ensembl GTF genes. 
## It will annotate the entire sequenced space with genes not just segments that meet a threshold as in in annotSeg.pl
##
## First input is annotation file downloaded from Ensembl (eg. Ensembl_v70_hs37d5.gtf).
## Second input is VCF file generated from ngs_cnv.m. 
## Third input is threshold for marking amplifications as PASS (e.g 0.58).
## Fourth input is threshold for marking deletions as PASS (e.g -0.9).
## Output is annotated VCF file.  This replaces the input VCF file.
## 
## ./annotSeg.pl /home/tgenref/pipeline_v0.3/tophat2/Ensembl_v70_hs37d5.gtf CNV.seg 0.58 -0.9
##
## Version 0.2
##
##Jessica Aldrich
##TGen
##October 1, 2013
##Updated: May 1, 2014
##Updated: June 5, 2015

$VERS=0.3;

$|=1;

#system("dos2unix $ARGV[1]");

# This loop loads in positions and the genes from CCDS into a hash:  gene{"chr5:1000000"}="gene|gene2";
my (%geneA,%loc,%loc2,%chr, %name);
my ($t,$en,$st,$i);
open (GTF, "$ARGV[0]");
LOOP:  while (<GTF>) {
  my @temp=split(/\t/);

  if($temp[8] ne "" && length($temp[0])!=0  && length($temp[3])!=0 && length($temp[4])!=0 && $temp[1] eq "protein_coding" && $temp[2] eq "CDS" )
        {
        my @info = split(/;/, $temp[8]);
        if(index($info[0],"gene_id")) { $info[0] =~ s/gene_id//g; $info[0] =~ s/\"//g; $info[0] =~ s/ //g;}

        if (exists($geneA{$info[0]})) {
                if($temp[3] < $loc{$info[0]}) {$loc{$info[0]}=$temp[3];}
                if($temp[4] >= $loc2{$info[0]}) {$loc2{$info[0]}=$temp[4];}
        } else {
        $geneA{$info[0]}=$info[0];

        $info[3] =~ s/gene_name//g;
        $info[3] =~ s/ //g;
        $info[3] =~ s/\"//g;
        $name{$info[0]}=$info[3];
	 
        $loc{$info[0]}=$temp[3];
        $loc2{$info[0]}=$temp[4];
        $chr{$info[0]}=$temp[0];

      }

}#else
#{
#	print "$temp[0] and $temp[8] \n";
#}
}

close(GTF);

my %gene;
foreach my $k (keys %geneA){
	$st=int($loc{$k}/100);
	$en=int($loc2{$k}/100);
	if ($st>$en) {$t=$en;$en=$st;$st=$t;}
        for ($i=$st-100;$i<=$en+100;++$i*100) {
		if ($chr{$k} eq "X") {$chr{$k}=23;}
		if ($chr{$k} eq "Y") {$chr{$k}=24;}
                if (exists($gene{"$chr{$k}_$i"})) {
                        $gene{"$chr{$k}_$i"}=join("|",$gene{"$chr{$k}_$i"},$name{$k});
                } else {
                        $gene{"$chr{$k}_$i"}=$name{$k};
                }
 }
}

##################################################
## Read in VCF file produces by ngs_cnv.m and annotate with CCDS genes
open (FILE, "$ARGV[1]");

$tmpfile="$ARGV[1].vcf";
open (OFILE,">",$tmpfile);

$dupThreshold = $ARGV[2];
$delThreshold = $ARGV[3];

print OFILE "##fileformat=VCFv4.1\n";
print OFILE "##INFO=<ID=IMPRECISE,Number=0,Type=Flag,Description=\"Imprecise structural variation\">\n";
print OFILE "##INFO=<ID=END,Number=1,Type=Integer,Description=\"End position of the variant described in this record\">\n";
print OFILE "##INFO=<ID=SVLEN,Number=.,Type=Integer,Description=\"Length between POS and END\">\n";
print OFILE "##INFO=<ID=SVTYPE,Number=1,Type=String,Description=\"Type of structural variant\">\n";
print OFILE "##INFO=<ID=LOG2FC,Number=.,Type=Float,Description=\"Log2 Fold Change\">\n";
print OFILE "##INFO=<ID=GENE,Number=.,Type=String,Description=\"Gene name\">\n";
print OFILE "##ALT=<ID=DEL,Description=\"Deletion\">\n";
print OFILE "##ALT=<ID=DUP,Description=\"Duplication\">\n";
print OFILE "##ALT=<ID=NOCALL,Description=\"Copy Neutral\">\n";
print OFILE "##source=\"annotSeg.pl v$VERS\"\n";

print OFILE "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n";

LOOP: while (<FILE>) {
  chomp();
  $line=$_;
  @temp=split(/\t/,$line);

  if($temp[5]>$dupThreshold){
        $alt="<DUP>";
  }
  elsif($temp[5]<$delThreshold){
        $alt="<DEL>";
  }
  else{
	$alt="<NOCALL>";
  }

  $qual=abs($temp[5]);

  if ($temp[0] =~/^\"ID\"/) {next LOOP;}
  
  $st=int($temp[2]/100);
  $en=int($temp[3]/100);
  @vals=();

  #if(int($temp[4])<10000 && abs($temp[5]*1)>=0.5){
  if($alt eq "<DUP>" || $alt eq "<DEL>"|| $alt eq "<NOCALL>"){
  for ($i=$st-100;$i<=$en+100;++$i*100) {
       push(@vals,"$temp[1]_$i");
     }
  #$en=int($temp[3]);
  @gns=();
  %seen=();
  foreach $val (@vals){

	if (exists($gene{$val})) {	
 
   		foreach $found (split(/\|/,$gene{$val})){
		next if ($seen{$found});
        	$seen{$found}=1;
		push(@gns,$found);
   		}
	}
  }

  if (@gns){
	$vcfline="$temp[1]\t$temp[2]\t$temp[3]\tN\t$alt\t$qual\tPASS\tIMPRECISE;SVTYPE=$alt;END=$temp[3];SVLEN=$temp[4];LOG2FC=$temp[5]";
	$genes=join(",",@gns);
	print OFILE "$vcfline;GENE=$genes\n";
  }
  else{
	print OFILE "$temp[1]\t$temp[2]\t$temp[3]\tN\t$alt\t$qual\tPASS\tIMPRECISE;SVTYPE=$alt;END=$temp[3];SVLEN=$temp[4];LOG2FC=$temp[5]\n";
  }
 }else{
	print OFILE "$temp[1]\t$temp[2]\t$temp[3]\tN\t$alt\t$qual\t.\tIMPRECISE;SVTYPE=$alt;END=$temp[3];SVLEN=$temp[4];LOG2FC=$temp[5]\n";
 }
}

close(OFILE);
close(FILE);
