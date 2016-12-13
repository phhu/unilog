#!/usr/bin/perl

#This is a script which allows for easy logging via HTTP
# unilog.pl?_logname=nameOfLog&_pw=password&_rpw=readPassword&values=....
# unilog.pl?_logname=testlog&value1=1000&value2=false&bln_Switch=no&txt_Name=value&date_CreateDate=01-jan-2008

#SOME DEVELOPMENT NOTES:

# unilog.pl?_logname=testlog[&_view=XML|HTML|CSV]   - this would return the data (or return from issqueries?). If it doesn't exist don't create it.
#
# Might as well create the log if it doesn't exist.... If create fails cos one already exists, then it'll just get added anyway. (Just allow for easy checking of existing names)
# therefore reasonably obscure log names would be required (or restrict by requestor IP or something stupid like that)
# Types 0123456789
# Date
# Time
# Datetime
# Integer
# Curr
# Text
# ...or just do them all as text / varchar?? - since they're strings anyway - but would be a pain for queries
# ...types only when there's a prefix (bln_, int_ , date_, time_, dt_, curr_, text_ - otherwise do text columns?
# ...Or try to guess? But this could be problematic.
# ...

# use issqueries to do rent-a-query - list of all tables in logs, possibly strip the type prefixes here?
#
# Possibility to return a file??
# Possibility to import a file rather than just a row at a time? How to send an attachment

#unilog needs to be able to handle many-to-many joins - with a filter? 
#E.g. 
#Field in log - join table (table name specifies joined tables) (_id1, _id2) - other log

#Run on https for security??? 

use strict;
use CGI qw(:standard);
use DBI;
#use Time::Local;
#use XML::Simple;
#use Data::Dump qw(dump ddx dd);

#Set output to utf-8 and force oracle to utf8
binmode(STDOUT, ":utf8");

my $q = new CGI;
my $i = 0 ;    #counter

my $dsn;my $dbh; 
$dsn = "DBI:mysql:database=unilogs;host=localhost;port=3306";

#get feedback
my $results = '';
my $feedback = getParam("_feedback","") eq 'on' ? 1:0;
my $logname;
# ************************* DEFINE SUBS ****************************

sub getParam($$){
	return $q->param($_[0]) ? $q->param($_[0]) : $_[1] ;
}

sub doFeedback($){
	$results .= $_[0] . "\n\n";
}

sub endIt($){

	my $output; my $statusCode;
	
	if ($_[0] eq 'OK') {
		$output = 'OK';
		$statusCode = 200;
	}
	else{
		$output = "FAILED \n\n" . $_[0];
		$statusCode = 200;
		eval{$dbh->rollback;};
	}	

	print $q->header(-charset=>"utf-8", -status=>$statusCode);  
	print "<html><head><title>$logname - UNILOG</title></head><body>";
	print $output ;
	if($feedback){print "\n\n<pre>$results</pre>";}
	print "</body></html>";

	eval{$dbh->disconnect();};

	exit;
}

my %colTypes = (
    bln => 'bit',
    txt => 'text',
    int => 'int',
    flt => 'float',
    curr => 'DECIMAL(17,2)'
);

#returns the column type based on a param name
sub getColType($){
	my $colname = $_[0];
  my @match = grep($colname =~ /^$_\_/  ,keys %colTypes);
  
	if (@match){return $colTypes{$match[0]};}
	else{return "varchar(256)";}
}

#this makes sure that the values are appropriate for the type of the field 
#and puts quotes on where necessary
sub getParamValue($){
	
	my $paramName = $_[0];
	my $paramValue = $q->param($paramName);
	my $paramType = [grep($paramName =~ /^$_\_/  ,keys %colTypes)]->[0];
	my $retVal;
	
	if ($paramType eq 'bln'){
		$retVal = $paramValue ? 1 : 0;
		if ($paramValue =~ /^(false|no|off)$/){$retVal = 0;}
	}
	elsif ($paramType =~ /^(int|flt|curr)$/i){
		$paramValue =~ s/[ ,]//g;					#take out spaces and commas
		if ($paramValue =~ /^-?\d*(\.\d*)?/ ){$retVal = $paramValue;}
		else{$retVal = 'null';}
	}
	elsif ($paramType eq 'txt'){
		$retVal = "'$paramValue'";
	}
	else{
		$retVal = "'$paramValue'";
	}
	return $retVal;
}

# ********************* get params ************************	

#get logname
$logname = getParam("_logname","");
$logname =~ s/^_//;																					#don't allow log names beginning with "_"
unless ($logname){endIt "No log name! Exiting";}	
if (length($logname) > 64){endIt "Log name '$logname' longer than 64 characters! Exiting";}
$logname =~ s/ /_/g;   			# replace spaces with _
if ($logname =~ /[^a-z0-9_\-]/i){endIt "Illegal characters in log name '$logname'. Only a-z, 0-9, _ and - are allowed. Spaces will be replaced with '_' Exiting";}
	
doFeedback 'UNILOG FEEDBACK ON...';
doFeedback "Logname: $logname";	

#get password
my $pw = getParam("_pw","");
#doFeedback "Password: $pw";	
my $readPw = getParam("_readpw","");	
my $action = getParam("_action","");
my $logTitle = getParam("_title","");
my $logDesc = getParam("_desc","");

#get all params into an array
my @allParams = $q->param;

#get params without leading "_" into array
my @params;
foreach(@allParams){unless ($_ =~ m/^_/){push @params, $_;}}
doFeedback 'PARAMS ARE: ' . join(',', @params);

#check there's at least one param - otherwise skip to displaying data? 
unless (@params){endIt "No params ($#params). Will display data...\n\n";}

#check that none of the param names are too long (64 char limit)
my $longParams = '';
foreach (@params){if (length > 64){$longParams .= "$_\n";}}
if ($longParams){endIt "Param names too long:\n$longParams";}

# ******************* connect ********************************

eval{$dbh = DBI->connect($dsn, 'unilog', 'd3nn1s',{'RaiseError' => 1, 'AutoCommit' => 0});};
if ($@){endIt "Database connection not possible: $@" ;}

#get columns
my $createTable="";
eval{$createTable = ${$dbh->selectall_arrayref("SHOW create table $logname")}[0][1];};

#if table doesn't exist then we need to create it
if ($@){
	doFeedback "Cannot find table, so need to create it";
	eval{$dbh->do("delete from _logInfo where logname = '$logname';");};
	if ($@){endIt "Error deleting existing logInfo entry: $@";}
	eval{$dbh->do("insert into _logInfo (LogName, Creator_IP, Creator_RemoteUser, Password, ReadPassword) value ('$logname', '" . $ENV{REMOTE_ADDR} . "' , '" . $ENV{REMOTE_USER} . "','$pw', '$readPw')");};
	if ($@){endIt "Error creating logInfo: $@";}
	doFeedback "LOG TITLE: $logTitle";
	if ($logTitle){
		eval{$dbh->do('update _logInfo set displayTitle = ? where LogName = ?', undef, ($logTitle, $logname));};
		if ($@){doFeedback "Error updating log title: $@";}
	}
	if ($logDesc){
		eval{$dbh->do('update _logInfo set Description = ? where LogName = ?', undef, ($logDesc, $logname));};
		if ($@){doFeedback "Error updating log title: $@";}
	}	
	eval{$dbh->do("CREATE TABLE $logname (
   _ID BIGINT(20) AUTO_INCREMENT NOT NULL,
   _Timestamp TIMESTAMP,
   _RequestorIP VARCHAR(40),
   _RequestorRemoteUser VARCHAR(256),
  PRIMARY KEY (_ID)
	) ENGINE = myisam ROW_FORMAT = DEFAULT;");};
	if ($@){endIt "Error creating table: $@";}
	else{doFeedback "Table $logname created.";}
}

#get password etc

my $logParams;
#eval{$pwFromDb = ${$dbh->selectall_arrayref("select password from _loginfo where logname = '$logname'")}[0][0];};
eval{$logParams = $dbh->selectall_arrayref("select password from _loginfo where logname = '$logname'");};
if ($@){doFeedback "Error getting db params: $@";}
#doFeedback
my $pwFromDb = ${$logParams}[0][0];

#doFeedback "PWfromDB: $pwFromDb";

#check password if one is set
if ($pwFromDb){
	unless ($pw eq $pwFromDb){endIt 'Incorrect password'}
}

#get columns from the createtable value (if there aren't any it'll just be an empty array.
my @columns; my $tmpCol;
while ($createTable =~ m/(CREATE TABLE |PRIMARY KEY  \()?`.*?`/g) {
	$tmpCol = $&; $tmpCol =~ s/`//g;
	unless ($tmpCol =~ m/^(_|CREATE TABLE |PRIMARY KEY  \()/){											#get rid of primary key, table name and columns beginning with _
  	push(@columns, $tmpCol); 
	}
}

#check if any columns need to be created
my @colsToCreate; my $tmpParam;
foreach (@params){
	$tmpParam = $_;
	unless (grep lc($_) eq lc($tmpParam), @columns){push @colsToCreate, $tmpParam;}
}

#create required columns
if (@colsToCreate){
	doFeedback "Cols to create are:" . join(',',@colsToCreate);
	my $colCreateSQL = "alter table $logname add (";										
	foreach (@colsToCreate){$colCreateSQL .= "$_ " . getColType($_) . ','}						# put in the cols to cretae
	$colCreateSQL =~ s/,$/)/;																													#replace last comma with a close bracket
	doFeedback "COL CREATE SQL: $colCreateSQL";
	eval{$dbh->do($colCreateSQL);};
	if ($@){endIt "\nError creating columns: $@";}
}

#insert the data	
#INSERT INTO table_name (column1, column2, column3,...) VALUES (value1, value2, value3,...)
if ($action ne 'create'){
	my @paramValues;
	foreach(@params){push @paramValues, getParamValue($_);}
	my $insertSQL = "INSERT INTO $logname (_RequestorIP,_RequestorRemoteUser," . join(',',@params) . ")\n VALUES ('" . $ENV{REMOTE_ADDR} . "','" . $ENV{REMOTE_USER} . "'," . join(',',@paramValues) . ')';
	doFeedback "INSERT SQL: $insertSQL";
	
	eval{$dbh->do($insertSQL);};
	if ($@){doFeedback "Error inserting row: $@";$dbh->rollback;endIt 'ERROR' . $insertSQL;}
	else{$dbh->commit;doFeedback "Data inserted";endIt 'OK';}
}
else{
	doFeedback "Create only: no data inserted. Log either already exists or it has been created.";
	$dbh->commit;endIt 'OK';

}
## ************************************************* END OUTPUT ********************************************

#this shouldn't run
$dbh->disconnect();
doFeedback 'ENDING';
exit;