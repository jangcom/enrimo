@echo off
set rpt_path=./lines_counted
set enrimo_path=..
set file1=%enrimo_path%/enrimo.pl

lcounter.pl --path=%rpt_path% %file1%
