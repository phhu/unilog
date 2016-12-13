# unilog
Perl cgi script allowing on the fly creation of databases logs using HTTP calls. 

This is useful for add hoc usage because no additional setup is required to create a new log or add to it - just make an HTTP GET call from anywhere.

E.g. 

unilog.pl?_logname=testlog&value1=1000&value2=false&bln_Switch=no&txt_Name=value&date_CreateDate=01-jan-2008

Would create or add to a database table called "testlog" with fields value1 etc.

The database of course needs to be set up and connected to. Perl DBI is used to do this.
