
ODIR=Release

PGM1=XmsAlloc
PGM2=XmsFree
PGM3=XmsLock
PGM4=XmsReal
PGM5=XmsUlock
PGM6=XmsCopy
PGM7=XmsUmb
PGM8=XmsInfo
PGM9=XmsHma

ALL: $(ODIR) $(ODIR)\$(PGM1).exe $(ODIR)\$(PGM2).exe \
	$(ODIR)\$(PGM3).exe $(ODIR)\$(PGM4).exe $(ODIR)\$(PGM5).exe $(ODIR)\$(PGM6).exe \
	$(ODIR)\$(PGM7).exe $(ODIR)\$(PGM8).exe $(ODIR)\$(PGM9).exe

$(ODIR):
	@mkdir $(ODIR)

.asm{$(ODIR)}.exe:
	@jwasm.exe -mz -nologo -Sg -Fl$*.lst -Fo$*.exe $<

clean:
	@erase $(ODIR)\*.exe
	@erase $(ODIR)\*.lst

