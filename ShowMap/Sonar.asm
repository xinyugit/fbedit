
IDD_DLGSONAR            equ 1500
IDC_TRBSONARGAIN        equ 1504
IDC_CHKSONARGAIN        equ 1503
IDC_TRBSONARPING        equ 1510
IDC_CHKSONARPING        equ 1509
IDC_TRBSONARRANGE       equ 1507
IDC_CHKSONARRANGE       equ 1506
IDC_CHKSONARBOTTOM		equ 1541
IDC_TRBSONARNOISE       equ 1501
IDC_TRBSONARREJECT		equ 1534
IDC_TRBSONARFISH        equ 1530
IDC_CHKSONARALARM       equ 1514
IDC_CHKFISHDEPTH		equ 1540
IDC_TRBSONARCHART       equ 1512
IDC_CHKCHARTPAUSE       equ 1532
IDC_TRBPINGTIMER        equ 1526
IDC_TRBSOUNDSPEED       equ 1528
IDC_BTNGD               equ 1502
IDC_BTNGU               equ 1505
IDC_BTNPU               equ 1508
IDC_BTNPD               equ 1511
IDC_BTNRU               equ 1513
IDC_BTNRD               equ 1516
IDC_BTNCU               equ 1517
IDC_BTNCD               equ 1518
IDC_BTNNU               equ 1519
IDC_BTNND               equ 1520
IDC_BTNNRD				equ 1535
IDC_BTNNRU				equ 1533
IDC_BTNPTU              equ 1525
IDC_BTNPTD              equ 1527
IDC_BTNSSU              equ 1523
IDC_BTNSSD              equ 1529
IDC_BTNFU               equ 1515
IDC_BTNFD               equ 1531
IDC_STCGAIN				equ 1521
IDC_STCPING				equ 1536
IDC_BTNSIGNALD          equ 1539
IDC_BTNSIGNALU          equ 1537
IDC_TRBSIGNAL           equ 1538

IDD_DLGSONARGAIN		equ 1600
IDC_BTNXD				equ 1604
IDC_BTNXU				equ 1601
IDC_BTNYD				equ 1602
IDC_BTNYU				equ 1605
IDC_CBORANGE			equ 1603
IDC_STCX				equ 1606
IDC_STCY				equ 1607
IDC_EDTGAINOFS			equ 1608
IDC_EDTGAINMAX			equ 1611
IDC_EDTGAINDEPTH		equ 1609
IDC_BTNCALCULATE		equ 1610

IDD_DLGSONARCOLOR		equ 1700
IDC_BTNDEFAULT			equ 1701
IDC_CHKGRAYSCALE		equ 1703

GAINXOFS				equ 60
GAINYOFS				equ 117
ZOOMHYSTERESIS			equ 7
DEPTHHYSTERESIS			equ 512

.code

GetRangePtr proc uses edx,RangeInx:DWORD

	mov		eax,RangeInx
	mov		edx,sizeof RANGE
	mul		edx
	ret

GetRangePtr endp

SetRange proc uses ebx,RangeInx:DWORD

	mov		eax,RangeInx
	mov		sonardata.RangeInx,al
	invoke GetRangePtr,eax
	mov		ebx,eax
	mov		eax,sonardata.sonarrange.pixeltimer[ebx]
	mov		sonardata.PixelTimer,ax
	mov		eax,sonardata.sonarrange.range[ebx]
	mov		sonardata.RangeVal,eax
	invoke wsprintf,addr sonardata.options.text,addr szFmtDec,eax
	ret

SetRange endp

;Description
;===========
;A short ping at 200KHz is transmitted at intervalls depending on range.
;From the time it takes for the echo to return we can calculate the depth.
;The ADC measures the strenght of the echo at intervalls depending on range
;and stores it in a 512 byte array.
;
;Speed of sound in water
;=======================
;Temp (C)    Speed (m/s)
;  0             1403
;  5             1427
; 10             1447
; 20             1481
; 30             1507
; 40             1526
;
;1450m/s is probably a good estimate.
;
;The timer is clocked at 40 MHz so it increments every 0,025us.
;For each tick the sound travels 1450 * 0,025 = 36,25 um or 36,25e-6 meters.

;Timer value calculation
;=======================
;Example 2m range and 40 MHz clock
;Timer period Tp=1/40MHz
;Each pixel is Px=2m/512.
;Time for each pixel is t=Px/1450/2
;Timer ticks Tt=t/Tp

;Formula T=((Range/512)/(1450/2))40000000

RangeToTimer proc RangeInx:DWORD
	LOCAL	tmp:DWORD

	invoke GetRangePtr,RangeInx
	mov		eax,sonardata.sonarrange.range[eax]
	mov		tmp,eax
	fild	tmp
	mov		tmp,MAXYECHO
	fild	tmp
	fdivp	st(1),st
	mov		eax,sonardata.SoundSpeed
	shr		eax,1			;Divide by 2 since it is the echo
	mov		tmp,eax
	fild	tmp
	fdivp	st(1),st
	mov		tmp,STM32_Clock
	fild	tmp
	fmulp	st(1),st
	fistp	tmp
	mov		eax,tmp
	dec		eax
	ret

RangeToTimer endp

SetupPixelTimer proc uses ebx edi
	
	xor		ebx,ebx
	mov		edi,offset sonardata.sonarrange
	.while ebx<sonardata.MaxRange
		invoke RangeToTimer,ebx
		mov		[edi].RANGE.pixeltimer,eax
		inc		ebx
		lea		edi,[edi+sizeof RANGE]
	.endw
	movzx	eax,sonardata.RangeInx
	invoke SetRange,eax
	ret

SetupPixelTimer endp

Resize_Image proc uses ebx esi edi,hBmp:HBITMAP,wt:DWORD,ht:DWORD
	LOCAL	iwt:DWORD
	LOCAL	iht:DWORD
	LOCAL	image1:DWORD
	LOCAL	image2:DWORD
	LOCAL	image3:DWORD
	LOCAL	gfx:DWORD
	LOCAL	lFormat:DWORD
	LOCAL	hBmpRet:HBITMAP

	invoke GdipCreateBitmapFromHBITMAP,hBmp,0,addr image1
	invoke GdipGetImageWidth,image1,addr iwt
	invoke GdipGetImageHeight,image1,addr iht
	invoke GdipGetImagePixelFormat,image1,addr lFormat
	.if ht>1024
		.while ht>1024
			shr		iht,1
			shr		ht,1
		.endw
		invoke GdipCloneBitmapAreaI,0,0,wt,iht,lFormat,image1,addr image3
		invoke GdipDisposeImage,image1
		mov		eax,image3
		mov		image1,eax
	.endif
	invoke GdipCreateBitmapFromScan0,wt,ht,0,lFormat,0,addr image2
	invoke GdipGetImageGraphicsContext,image2,addr gfx
	invoke GdipSetInterpolationMode,gfx,InterpolationModeNearestNeighbor
	invoke GdipDrawImageRectI,gfx,image1,0,0,wt,ht
	invoke GdipDisposeImage,image1
	invoke GdipCreateHBITMAPFromBitmap,image2,addr hBmpRet,0
	invoke GdipDisposeImage,image2
	invoke GdipDeleteGraphics,gfx
	mov		eax,hBmpRet
	ret

Resize_Image endp

UpdateBitmap proc uses ebx esi edi,NewRange:DWORD
	LOCAL	rect:RECT
	LOCAL	hDC:HDC
	LOCAL	mDC:HDC
	LOCAL	wt:DWORD

	invoke GetDC,hSonar
	mov		hDC,eax
	invoke CreateCompatibleDC,hDC
	mov		mDC,eax
	invoke ReleaseDC,hSonar,hDC
	mov		rect.left,0
	mov		rect.top,0
	mov		rect.right,MAXXECHO
	mov		rect.bottom,MAXYECHO
	invoke FillRect,sonardata.mDC,addr rect,sonardata.hBrBack
	mov		esi,offset sonardata.sonarbmp
	xor		ebx,ebx
	.while ebx<MAXSONARBMP
		.if [esi].SONARBMP.hBmp
			mov		eax,[esi].SONARBMP.xpos
			add		eax,[esi].SONARBMP.wt
			.if sdword ptr eax>0 && [esi].SONARBMP.wt
				invoke GetRangePtr,[esi].SONARBMP.RangeInx
				mov		ecx,sonardata.sonarrange.range[eax]
				mov		eax,MAXYECHO
				mul		ecx
				mov		ecx,NewRange
				div		ecx
				mov		edx,[esi].SONARBMP.wt
				invoke Resize_Image,[esi].SONARBMP.hBmp,edx,eax
				invoke SelectObject,mDC,eax
				push	eax
				invoke GetRangePtr,[esi].SONARBMP.RangeInx
				mov		ecx,sonardata.sonarrange.range[eax]
				mov		eax,MAXYECHO
				mul		ecx
				mov		ecx,NewRange
				div		ecx
				mov		edx,[esi].SONARBMP.wt
				mov		ecx,[esi].SONARBMP.xpos
				xor		edi,edi
				.if sdword ptr ecx<0
					neg		ecx
					mov		edi,ecx
					sub		edx,ecx
					xor		ecx,ecx
				.endif
				invoke BitBlt,sonardata.mDC,ecx,0,edx,eax,mDC,edi,0,SRCCOPY
				pop		eax
				invoke SelectObject,mDC,eax
				invoke DeleteObject,eax
			.else
				invoke DeleteObject,[esi].SONARBMP.hBmp
				mov		[esi].SONARBMP.hBmp,0
			.endif
		.endif
		lea		esi,[esi+sizeof SONARBMP]
		inc		ebx
	.endw
	invoke DeleteDC,mDC
	ret

UpdateBitmap endp

SonarUpdateProc proc uses ebx esi edi,nUpdate:DWORD
	LOCAL	rect:RECT
	LOCAL	buffer[256]:BYTE
	LOCAL	tmp:DWORD
	LOCAL	hDC:HDC
	LOCAL	mDC:HDC

	.if sonardata.hReplay
		call	Update
		;Update range
		movzx	eax,sonardata.EchoArray
		mov		sonardata.RangeInx,al
	.elseif sonardata.fSTLink
		call	Update
	.endif
	ret

SetBattery:
	.if eax!=sonardata.Battery
		mov		sonardata.Battery,eax
		mov		ecx,100
		mul		ecx
		mov		ecx,1740
		div		ecx
		invoke wsprintf,addr buffer,addr szFmtVolts,eax
		invoke strlen,addr buffer
		movzx	ecx,word ptr buffer[eax-1]
		shl		ecx,8
		mov		cl,'.'
		mov		dword ptr buffer[eax-1],ecx
		invoke strcat,addr buffer,addr szVolts
		invoke strcpy,addr mapdata.options.text[sizeof OPTIONS],addr buffer
		invoke InvalidateRect,hMap,NULL,TRUE
	.endif
	retn

SetWTemp:
	.if eax!=sonardata.WTemp
		mov		sonardata.WTemp,eax
		sub		eax,watertempoffset
		neg		eax
		mov		tmp,eax
		fild	tmp
		fld		watertempconv
		fdivp	st(1),st
		fistp	tmp
		.if sdword ptr tmp<0
			invoke wsprintf,addr buffer,addr szFmtDec3,tmp
		.else
			invoke wsprintf,addr buffer,addr szFmtDec2,tmp
		.endif
		invoke strlen,addr buffer
		movzx	ecx,word ptr buffer[eax-1]
		shl		ecx,8
		mov		cl,'.'
		mov		dword ptr buffer[eax-1],ecx
		invoke strcat,addr buffer,addr szCelcius
		invoke strcpy,addr sonardata.options.text[sizeof OPTIONS*2],addr buffer
	.endif
	retn

SetATemp:
	.if eax!=sonardata.ATemp
		mov		sonardata.ATemp,eax
		sub		eax,airtempoffset
		neg		eax
		mov		tmp,eax
		fild	tmp
		fld		airtempconv
		fdivp	st(1),st
		fistp	tmp
		.if sdword ptr tmp<0
			invoke wsprintf,addr buffer,addr szFmtDec3,tmp
		.else
			invoke wsprintf,addr buffer,addr szFmtDec2,tmp
		.endif
		invoke strlen,addr buffer
		movzx	ecx,word ptr buffer[eax-1]
		shl		ecx,8
		mov		cl,'.'
		mov		dword ptr buffer[eax-1],ecx
		invoke strcat,addr buffer,addr szCelcius
		invoke strcpy,addr mapdata.options.text[sizeof OPTIONS*2],addr buffer
	.endif
	retn

GetBitmap:
	invoke GetDC,hSonar
	mov		hDC,eax
	invoke CreateCompatibleDC,hDC
	mov		mDC,eax
	invoke CreateCompatibleBitmap,hDC,sonardata.sonarbmp.wt,MAXYECHO
	invoke SelectObject,mDC,eax
	push	eax
	invoke ReleaseDC,hSonar,hDC
	mov		eax,MAXXECHO
	sub		eax,sonardata.sonarbmp.wt
	invoke BitBlt,mDC,0,0,sonardata.sonarbmp.wt,MAXYECHO,sonardata.mDC,eax,0,SRCCOPY
	pop		eax
	invoke SelectObject,mDC,eax
	mov		sonardata.sonarbmp.hBmp,eax
	invoke DeleteDC,mDC
	retn

ScrollBitmapArray:
	lea		edi,sonardata.sonarbmp[sizeof SONARBMP*(MAXSONARBMP-1)]
	.if [edi].SONARBMP.hBmp
		invoke DeleteObject,[edi].SONARBMP.hBmp
	.endif
	mov		ebx,MAXSONARBMP-1
	.while ebx
		lea		esi,[edi-sizeof SONARBMP]
		invoke RtlMoveMemory,edi,esi,sizeof SONARBMP
		lea		edi,[edi-sizeof SONARBMP]
		dec		ebx
	.endw
	movzx	eax,sonardata.EchoArray
	mov		sonardata.sonarbmp.RangeInx,eax
	mov		sonardata.sonarbmp.xpos,MAXXECHO
	mov		sonardata.sonarbmp.wt,0
	mov		sonardata.sonarbmp.hBmp,0
	retn

UpdateBitmapArray:
	lea		edi,sonardata.sonarbmp[sizeof SONARBMP*(MAXSONARBMP-1)]
	mov		edx,MAXSONARBMP-1
	.while edx
		.if [edi].SONARBMP.hBmp
			dec		[edi].SONARBMP.xpos
			mov		eax,[edi].SONARBMP.xpos
			add		eax,[edi].SONARBMP.wt
			.if sdword ptr eax<=0
				;Delete the bitmap, it is no longer needed
				push	edx
				invoke DeleteObject,[edi].SONARBMP.hBmp
				pop		edx
				mov		[edi].SONARBMP.hBmp,0
			.endif
		.endif
		lea		edi,[edi-sizeof SONARBMP]
		dec		edx
	.endw
	.if [edi].SONARBMP.wt<MAXXECHO
		inc		[edi].SONARBMP.wt
		dec		[edi].SONARBMP.xpos
	.endif
	retn

Update:
	;Battery
	movzx	eax,sonardata.ADCBattery
	call	SetBattery
	;Water temprature
	movzx	eax,sonardata.ADCWaterTemp
	call	SetWTemp
	;Air temprature
	movzx	eax,sonardata.ADCAirTemp
	call	SetATemp
	.if nUpdate==1
		;Check if range is still the same
		movzx	eax,STM32Echo
		.if eax!=sonardata.sonarbmp.RangeInx
			;Get bitmap
			call	GetBitmap
			call	ScrollBitmapArray
			invoke GetRangePtr,sonardata.sonarbmp.RangeInx
			invoke UpdateBitmap,sonardata.sonarrange.range[eax]
		.endif
		call	UpdateBitmapArray
		mov		rect.left,0
		mov		rect.top,0
		mov		rect.right,MAXXECHO
		mov		rect.bottom,MAXYECHO
		invoke ScrollDC,sonardata.mDC,-1,0,addr rect,addr rect,NULL,NULL
		mov		rect.left,MAXXECHO-1
		mov		rect.top,0
		mov		rect.right,MAXXECHO
		mov		rect.bottom,MAXYECHO
		invoke FillRect,sonardata.mDC,addr rect,sonardata.hBrBack
		;Draw echo
		mov		ebx,1
		.while ebx<MAXYECHO
			movzx	eax,sonardata.EchoArray[ebx]
			.if eax
				.if sonardata.fGrayScale
					;Grayscale
					.if eax<72 && ebx<esi
						mov		eax,72
					.endif
					mov		ah,al
					shl		eax,8
					mov		al,ah
				.else
					;Color
					shr		eax,4
					mov		eax,sonardata.sonarcolor[eax*DWORD]
				.endif
				invoke SetPixel,sonardata.mDC,MAXXECHO-1,ebx,eax
			.endif
			lea		ebx,[ebx+1]
		.endw
		.if sonardata.fShowBottom && sonardata.dptinx && sonardata.prvdptinx; && !sonardata.nodptinx
			invoke CreatePen,PS_SOLID,5,0
			invoke SelectObject,sonardata.mDC,eax
			push	eax
			invoke MoveToEx,sonardata.mDC,MAXXECHO-2,sonardata.prvdptinx,NULL
			invoke LineTo,sonardata.mDC,MAXXECHO-1,sonardata.dptinx
			pop		eax
			invoke SelectObject,sonardata.mDC,eax
			invoke DeleteObject,eax
		.endif
	.endif
	.if nUpdate
		mov		ebx,sonardata.SignalBarWt
		mov		rect.left,0
		mov		rect.top,0
		mov		rect.right,ebx
		mov		rect.bottom,MAXYECHO
		invoke FillRect,sonardata.mDCS,addr rect,sonardata.hBrBack
		.if ebx>8
			;Draw signal bar
			mov		ebx,1
			.while ebx<MAXYECHO
				movzx	eax,STM32Echo[ebx]
				mov		ecx,sonardata.SignalBarWt
				mul		ecx
				shr		eax,8
				.if eax
					mov		edi,eax
					invoke MoveToEx,sonardata.mDCS,0,ebx,NULL
					invoke LineTo,sonardata.mDCS,edi,ebx
				.endif
				lea		ebx,[ebx+1]
			.endw
		.endif
	.endif
	mov		sonardata.PaintNow,0
	invoke InvalidateRect,hSonar,NULL,TRUE
	invoke UpdateWindow,hSonar
	retn

SonarUpdateProc endp

SonarOptionProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	hDC:HDC

	mov		eax,uMsg
	.if eax==WM_INITDIALOG
		.if sonardata.AutoRange
			invoke CheckDlgButton,hWin,IDC_CHKSONARRANGE,BST_CHECKED
		.endif
		.if sonardata.fShowBottom
			invoke CheckDlgButton,hWin,IDC_CHKSONARBOTTOM,BST_CHECKED
		.endif
		mov		eax,sonardata.MaxRange
		dec		eax
		shl		eax,16
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARRANGE,TBM_SETRANGE,FALSE,eax
		movzx	eax,sonardata.RangeInx
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARRANGE,TBM_SETPOS,TRUE,eax
		.if sonardata.AutoGain
			invoke CheckDlgButton,hWin,IDC_CHKSONARGAIN,BST_CHECKED
		.endif
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARGAIN,TBM_SETRANGE,FALSE,(4095 SHL 16)+0
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARGAIN,TBM_SETPOS,TRUE,sonardata.GainSet
		.if sonardata.AutoPing
			invoke CheckDlgButton,hWin,IDC_CHKSONARPING,BST_CHECKED
		.endif
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARPING,TBM_SETRANGE,FALSE,(MAXPING SHL 16)+0
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARPING,TBM_SETPOS,TRUE,sonardata.PingInit
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARNOISE,TBM_SETRANGE,FALSE,(255 SHL 16)+1
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARNOISE,TBM_SETPOS,TRUE,sonardata.NoiseLevel
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARREJECT,TBM_SETRANGE,FALSE,(3 SHL 16)+0
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARREJECT,TBM_SETPOS,TRUE,sonardata.NoiseReject
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARFISH,TBM_SETRANGE,FALSE,(3 SHL 16)+0
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARFISH,TBM_SETPOS,TRUE,sonardata.FishDetect
		invoke SendDlgItemMessage,hWin,IDC_TRBSIGNAL,TBM_SETRANGE,FALSE,(16 shl 16)+0
		mov		eax,sonardata.SignalBarWt
		shr		eax,4
		invoke SendDlgItemMessage,hWin,IDC_TRBSIGNAL,TBM_SETPOS,TRUE,eax
		.if sonardata.FishAlarm
			invoke CheckDlgButton,hWin,IDC_CHKSONARALARM,BST_CHECKED
		.endif
		.if sonardata.FishDepth
			invoke CheckDlgButton,hWin,IDC_CHKFISHDEPTH,BST_CHECKED
		.endif
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARCHART,TBM_SETRANGE,FALSE,(4 SHL 16)+1
		invoke SendDlgItemMessage,hWin,IDC_TRBSONARCHART,TBM_SETPOS,TRUE,sonardata.ChartSpeed
		invoke IsDlgButtonChecked,hWnd,IDC_CHKCHART
		.if eax
			invoke CheckDlgButton,hWin,IDC_CHKCHARTPAUSE,BST_CHECKED
		.endif
		invoke SendDlgItemMessage,hWin,IDC_TRBPINGTIMER,TBM_SETRANGE,FALSE,((STM32_PingTimer+1) SHL 16)+STM32_PingTimer-1
		movzx	eax,sonardata.PingTimer
		invoke SendDlgItemMessage,hWin,IDC_TRBPINGTIMER,TBM_SETPOS,TRUE,eax
		invoke SendDlgItemMessage,hWin,IDC_TRBSOUNDSPEED,TBM_SETRANGE,FALSE,((SOUNDSPEEDMAX) SHL 16)+SOUNDSPEEDMIN
		invoke SendDlgItemMessage,hWin,IDC_TRBSOUNDSPEED,TBM_SETPOS,TRUE,sonardata.SoundSpeed
		invoke ImageList_GetIcon,hIml,12,ILD_NORMAL
		mov		ebx,eax
		invoke SendDlgItemMessage,hWin,IDC_BTNNRD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNGD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNPD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNRD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNCD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNND,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNSSD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNPTD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNFD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNSIGNALD,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke ImageList_GetIcon,hIml,4,ILD_NORMAL
		mov		ebx,eax
		invoke SendDlgItemMessage,hWin,IDC_BTNNRU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNGU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNPU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNRU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNCU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNNU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNSSU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNPTU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNFU,BM_SETIMAGE,IMAGE_ICON,ebx
		invoke SendDlgItemMessage,hWin,IDC_BTNSIGNALU,BM_SETIMAGE,IMAGE_ICON,ebx
		;Subclass buttons to get autorepeat
		push	0
		push	IDC_BTNSIGNALD
		push	IDC_BTNSIGNALU
		push	IDC_BTNNRD
		push	IDC_BTNNRU
		push	IDC_BTNGD
		push	IDC_BTNGU
		push	IDC_BTNPD
		push	IDC_BTNPU
		push	IDC_BTNRD
		push	IDC_BTNRU
		push	IDC_BTNCD
		push	IDC_BTNCU
		push	IDC_BTNND
		push	IDC_BTNNU
		push	IDC_BTNSSD
		push	IDC_BTNSSU
		push	IDC_BTNPTD
		push	IDC_BTNPTU
		push	IDC_BTNFD
		mov		eax,IDC_BTNFU
		.while eax
			invoke GetDlgItem,hWin,eax
			invoke SetWindowLong,eax,GWL_WNDPROC,offset ButtonProc
			mov		lpOldButtonProc,eax
			pop		eax
		.endw
		call	SetGain
		call	SetPing
	.elseif eax==WM_COMMAND
		mov		edx,wParam
		movzx	eax,dx
		shr		edx,16
		.if edx==BN_CLICKED
			.if eax==IDOK
				invoke SendMessage,hWin,WM_CLOSE,NULL,FALSE
			.elseif eax==IDC_CHKSONARGAIN
				xor		sonardata.AutoGain,1
				inc		sonardata.fGainUpload
			.elseif eax==IDC_CHKSONARPING
				xor		sonardata.AutoPing,1
			.elseif eax==IDC_CHKSONARRANGE
				xor		sonardata.AutoRange,1
				mov		eax,BST_UNCHECKED
				.if sonardata.AutoRange
					mov		eax,BST_CHECKED
				.endif
				invoke CheckDlgButton,hWnd,IDC_CHKAUTORANGE,eax
			.elseif eax==IDC_CHKSONARBOTTOM
				xor		sonardata.fShowBottom,1
				mov		eax,BST_UNCHECKED
				.if sonardata.fShowBottom
					mov		eax,BST_CHECKED
				.endif
				invoke CheckDlgButton,hWnd,IDC_CHKSONARBOTTOM,eax
			.elseif eax==IDC_CHKCHARTPAUSE
				invoke IsDlgButtonChecked,hWin,IDC_CHKCHARTPAUSE
				.if eax
					mov		eax,BST_CHECKED
				.endif
				invoke CheckDlgButton,hWnd,IDC_CHKCHART,eax
			.elseif eax==IDC_CHKSONARALARM
				xor		sonardata.FishAlarm,1
			.elseif eax==IDC_CHKFISHDEPTH
				xor		sonardata.FishDepth,1
			.elseif eax==IDC_BTNGD
				.if sonardata.GainSet
					dec		sonardata.GainSet
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARGAIN,TBM_SETPOS,TRUE,sonardata.GainSet
					inc		sonardata.fGainUpload
					call	SetGain
				.endif
			.elseif eax==IDC_BTNGU
				.if sonardata.GainSet<4095
					inc		sonardata.GainSet
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARGAIN,TBM_SETPOS,TRUE,sonardata.GainSet
					inc		sonardata.fGainUpload
					call	SetGain
				.endif
			.elseif eax==IDC_BTNPD
				.if sonardata.PingInit>1
					dec		sonardata.PingInit
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARPING,TBM_SETPOS,TRUE,sonardata.PingInit
					call	SetPing
				.endif
			.elseif eax==IDC_BTNPU
				.if sonardata.PingInit<MAXPING
					inc		sonardata.PingInit
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARPING,TBM_SETPOS,TRUE,sonardata.PingInit
					call	SetPing
				.endif
			.elseif eax==IDC_BTNRD
				.if sonardata.RangeInx
					mov		sonardata.dptinx,0
					dec		sonardata.RangeInx
					movzx	eax,sonardata.RangeInx
					invoke SetRange,eax
					movzx	eax,sonardata.RangeInx
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARRANGE,TBM_SETPOS,TRUE,eax
					inc		sonardata.fGainUpload
				.endif
			.elseif eax==IDC_BTNRU
				mov		eax,sonardata.MaxRange
				dec		eax
				.if al>sonardata.RangeInx
					mov		sonardata.dptinx,0
					inc		sonardata.RangeInx
					movzx	eax,sonardata.RangeInx
					invoke SetRange,eax
					movzx	eax,sonardata.RangeInx
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARRANGE,TBM_SETPOS,TRUE,eax
					inc		sonardata.fGainUpload
				.endif
			.elseif eax==IDC_BTNND
				.if sonardata.NoiseLevel>1
					dec		sonardata.NoiseLevel
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARNOISE,TBM_SETPOS,TRUE,sonardata.NoiseLevel
				.endif
			.elseif eax==IDC_BTNNU
				.if sonardata.NoiseLevel<255
					inc		sonardata.NoiseLevel
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARNOISE,TBM_SETPOS,TRUE,sonardata.NoiseLevel
				.endif
			.elseif eax==IDC_BTNNRD
				.if sonardata.NoiseReject
					dec		sonardata.NoiseReject
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARREJECT,TBM_SETPOS,TRUE,sonardata.NoiseReject
				.endif
			.elseif eax==IDC_BTNNRU
				.if sonardata.NoiseReject<3
					inc		sonardata.NoiseReject
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARREJECT,TBM_SETPOS,TRUE,sonardata.NoiseReject
				.endif
			.elseif eax==IDC_BTNFD
				.if sonardata.FishDetect
					dec		sonardata.FishDetect
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARFISH,TBM_SETPOS,TRUE,sonardata.FishDetect
				.endif
			.elseif eax==IDC_BTNFU
				.if sonardata.FishDetect<3
					inc		sonardata.FishDetect
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARFISH,TBM_SETPOS,TRUE,sonardata.FishDetect
				.endif
			.elseif eax==IDC_BTNCD
				.if sonardata.ChartSpeed>1
					dec		sonardata.ChartSpeed
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARCHART,TBM_SETPOS,TRUE,sonardata.ChartSpeed
				.endif
			.elseif eax==IDC_BTNCU
				.if sonardata.ChartSpeed<4
					inc		sonardata.ChartSpeed
					invoke SendDlgItemMessage,hWin,IDC_TRBSONARCHART,TBM_SETPOS,TRUE,sonardata.ChartSpeed
				.endif
			.elseif eax==IDC_BTNPTD
				.if sonardata.PingTimer>STM32_PingTimer-2
					dec		sonardata.PingTimer
					movzx	eax,sonardata.PingTimer
					invoke SendDlgItemMessage,hWin,IDC_TRBPINGTIMER,TBM_SETPOS,TRUE,eax
				.endif
			.elseif eax==IDC_BTNPTU
				.if sonardata.PingTimer<STM32_PingTimer+2
					inc		sonardata.PingTimer
					movzx	eax,sonardata.PingTimer
					invoke SendDlgItemMessage,hWin,IDC_TRBPINGTIMER,TBM_SETPOS,TRUE,eax
				.endif
			.elseif eax==IDC_BTNSSU
				.if sonardata.SoundSpeed<SOUNDSPEEDMAX
					inc		sonardata.SoundSpeed
					invoke SendDlgItemMessage,hWin,IDC_TRBSOUNDSPEED,TBM_SETPOS,TRUE,sonardata.SoundSpeed
					invoke SetupPixelTimer
				.endif
			.elseif eax==IDC_BTNSSD
				.if sonardata.SoundSpeed>SOUNDSPEEDMIN
					dec		sonardata.SoundSpeed
					invoke SendDlgItemMessage,hWin,IDC_TRBSOUNDSPEED,TBM_SETPOS,TRUE,sonardata.SoundSpeed
					invoke SetupPixelTimer
				.endif
			.elseif eax==IDC_BTNSIGNALU
				.if sonardata.SignalBarWt<256+8
					add		sonardata.SignalBarWt,16
					mov		eax,sonardata.SignalBarWt
					shr		eax,4
					invoke SendDlgItemMessage,hWin,IDC_TRBSIGNAL,TBM_SETPOS,TRUE,eax
					call	SetSignal
				.endif
			.elseif eax==IDC_BTNSIGNALD
				.if sonardata.SignalBarWt>8
					sub		sonardata.SignalBarWt,16
					mov		eax,sonardata.SignalBarWt
					shr		eax,4
					invoke SendDlgItemMessage,hWin,IDC_TRBSIGNAL,TBM_SETPOS,TRUE,eax
					call	SetSignal
				.endif
			.endif
		.endif
	.elseif eax==WM_HSCROLL
		invoke SendMessage,lParam,TBM_GETPOS,0,0
		mov		ebx,eax
		invoke GetDlgCtrlID,lParam
		.if eax==IDC_TRBSONARGAIN
			mov		sonardata.GainSet,ebx
			inc		sonardata.fGainUpload
			call	SetGain
		.elseif eax==IDC_TRBSONARRANGE
			mov		sonardata.RangeInx,bl
			invoke SetRange,ebx
			inc		sonardata.fGainUpload
		.elseif eax==IDC_TRBSONARNOISE
			mov		sonardata.NoiseLevel,ebx
		.elseif eax==IDC_TRBSONARREJECT
			mov		sonardata.NoiseReject,ebx
		.elseif eax==IDC_TRBSONARPING
			mov		sonardata.PingInit,ebx
			call	SetPing
		.elseif eax==IDC_TRBSONARFISH
			mov		sonardata.FishDetect,ebx
		.elseif eax==IDC_TRBSONARCHART
			mov		sonardata.ChartSpeed,ebx
		.elseif eax==IDC_TRBPINGTIMER
			mov		sonardata.PingTimer,bl
		.elseif eax==IDC_TRBSOUNDSPEED
			mov		sonardata.SoundSpeed,ebx
			invoke SetupPixelTimer
		.elseif eax==IDC_TRBSIGNAL
			shl		ebx,4
			add		ebx,8
			.if ebx!=sonardata.SignalBarWt
				mov		sonardata.SignalBarWt,ebx
				call	SetSignal
			.endif
		.endif
	.elseif eax==WM_CLOSE
		invoke DestroyWindow,hWin
	.else
		mov		eax,FALSE
		ret
	.endif
	mov		eax,TRUE
	ret

SetGain:
	invoke SetDlgItemInt,hWin,IDC_STCGAIN,sonardata.GainSet,FALSE
	retn

SetPing:
	invoke SetDlgItemInt,hWin,IDC_STCPING,sonardata.PingInit,FALSE
	retn

SetSignal:
	invoke GetDC,hWin
	mov		hDC,eax
	push	sonardata.hBmpOldS
	invoke CreateCompatibleBitmap,hDC,sonardata.SignalBarWt,MAXYECHO
	mov		sonardata.hBmpS,eax
	invoke SelectObject,sonardata.mDCS,eax
	mov		sonardata.hBmpOldS,eax
	invoke ReleaseDC,hWin,hDC
	pop		eax
	invoke DeleteObject,eax
	invoke SonarUpdateProc,2
	retn

SonarOptionProc endp

SonarGainOptionProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	rect:RECT
	LOCAL	ps:PAINTSTRUCT
	LOCAL	buffer[256]:BYTE
	LOCAL	tmp:DWORD
	LOCAL	max:DWORD
	LOCAL	ftmp:REAL8
	LOCAL	frng:REAL8
	LOCAL	gain[MAXYECHO+1]:WORD

	.data?
		xrange	DWORD ?
		xp		DWORD ?
		yp		DWORD ?
		pgain	DWORD ?
	.code

	mov		eax,uMsg
	.if eax==WM_INITDIALOG
		mov		esi,offset sonardata.sonarrange
		xor		ebx,ebx
		.while ebx<sonardata.MaxRange
			mov		eax,[esi].RANGE.range
			invoke wsprintf,addr buffer,addr szFmtDec,eax
			invoke SendDlgItemMessage,hWin,IDC_CBORANGE,CB_ADDSTRING,0,addr buffer
			lea		esi,[esi+sizeof RANGE]
			inc		ebx
		.endw
		invoke SendDlgItemMessage,hWin,IDC_CBORANGE,CB_SETCURSEL,0,0
		mov		xp,0
		mov		yp,0
		invoke ImageList_GetIcon,hIml,0,ILD_NORMAL
		invoke SendDlgItemMessage,hWin,IDC_BTNYU,BM_SETIMAGE,IMAGE_ICON,eax
		invoke ImageList_GetIcon,hIml,8,ILD_NORMAL
		invoke SendDlgItemMessage,hWin,IDC_BTNYD,BM_SETIMAGE,IMAGE_ICON,eax
		invoke ImageList_GetIcon,hIml,12,ILD_NORMAL
		invoke SendDlgItemMessage,hWin,IDC_BTNXD,BM_SETIMAGE,IMAGE_ICON,eax
		invoke ImageList_GetIcon,hIml,4,ILD_NORMAL
		invoke SendDlgItemMessage,hWin,IDC_BTNXU,BM_SETIMAGE,IMAGE_ICON,eax
		invoke SetDlgItemInt,hWin,IDC_EDTGAINOFS,sonardata.gainofs,FALSE
		invoke SendDlgItemMessage,hWin,IDC_EDTGAINOFS,EM_LIMITTEXT,4,0
		invoke SetDlgItemInt,hWin,IDC_EDTGAINMAX,sonardata.gainmax,FALSE
		invoke SendDlgItemMessage,hWin,IDC_EDTGAINMAX,EM_LIMITTEXT,4,0
		invoke SetDlgItemInt,hWin,IDC_EDTGAINDEPTH,sonardata.gaindepth,FALSE
		invoke SendDlgItemMessage,hWin,IDC_EDTGAINDEPTH,EM_LIMITTEXT,3,0
		;Subclass buttons to get autorepeat
		push	0
		push	IDC_BTNXD
		push	IDC_BTNXU
		push	IDC_BTNYD
		mov		eax,IDC_BTNYU
		.while eax
			invoke GetDlgItem,hWin,eax
			invoke SetWindowLong,eax,GWL_WNDPROC,offset ButtonProc
			mov		lpOldButtonProc,eax
			pop		eax
		.endw
	.elseif eax==WM_COMMAND
		mov		edx,wParam
		movzx	eax,dx
		shr		edx,16
		.if edx==BN_CLICKED
			.if eax==IDOK
				xor		ebx,ebx
				mov		esi,offset sonardata.sonarrange
				.while ebx<sonardata.MaxRange
					push	ebx
					push	esi
					mov		szbuff,0
					invoke PutItemInt,addr szbuff,[esi].RANGE.range
					invoke PutItemInt,addr szbuff,[esi].RANGE.mindepth
					invoke PutItemInt,addr szbuff,[esi].RANGE.interval
					invoke PutItemInt,addr szbuff,[esi].RANGE.pingadd
					xor		ebx,ebx
					.while ebx<17
						invoke PutItemInt,addr szbuff,[esi].RANGE.gain[ebx*DWORD]
						inc		ebx
					.endw
					mov		ebx,[esi].RANGE.nticks
					lea		esi,[esi].RANGE.scale
					.while sdword ptr ebx>=0
						invoke PutItemStr,addr szbuff,esi
						invoke strlen,esi
						lea		esi,[esi+eax+1]
						dec		ebx
					.endw
					pop		esi
					pop		ebx
					invoke wsprintf,addr buffer,addr szFmtDec,ebx
					invoke WritePrivateProfileString,addr szIniSonarRange,addr buffer,addr szbuff+1,addr szIniFileName
					lea		esi,[esi+sizeof RANGE]
					inc		ebx
				.endw
				mov		szbuff,0
				invoke PutItemInt,addr szbuff,sonardata.gainofs
				invoke PutItemInt,addr szbuff,sonardata.gainmax
				invoke PutItemInt,addr szbuff,sonardata.gaindepth
				invoke WritePrivateProfileString,addr szIniSonarRange,addr szIniGainDef,addr szbuff+1,addr szIniFileName
				invoke EndDialog,hWin,NULL
			.elseif eax==IDC_BTNCALCULATE
				invoke GetDlgItemInt,hWin,IDC_EDTGAINOFS,NULL,FALSE
				mov		sonardata.gainofs,eax
				invoke GetDlgItemInt,hWin,IDC_EDTGAINMAX,NULL,FALSE
				mov		sonardata.gainmax,eax
				invoke GetDlgItemInt,hWin,IDC_EDTGAINDEPTH,NULL,FALSE
				mov		sonardata.gaindepth,eax
				mov		eax,sonardata.gainmax
				sub		eax,sonardata.gainofs
				mov		tmp,eax
				mov		max,eax
				fild	tmp
				mov		eax,sonardata.gaindepth
				mov		tmp,eax
				fidiv	tmp
				fstp	ftmp
				mov		esi,offset sonardata.sonarrange
				xor		ebx,ebx
				.while ebx<sonardata.MaxRange
					fld		ftmp
					mov		eax,[esi].RANGE.range
					mov		tmp,eax
					fimul	tmp
					fidiv	dd512
					fstp	frng
					fldz
					xor		edi,edi
					xor		edx,edx
					.while edi<MAXYECHO
						fist	tmp
						mov		ecx,edi
						and		ecx,31
						.if !ecx
							mov		eax,tmp
							.if eax>max
								mov		eax,max
							.endif
							mov		[esi].RANGE.gain[edx*DWORD],eax
							inc		edx
						.endif
						fadd	frng
						inc		edi
					.endw
					fistp	tmp
					mov		eax,tmp
					.if eax>max
						mov		eax,max
					.endif
					mov		[esi].RANGE.gain[edx*DWORD],eax
					lea		esi,[esi+sizeof RANGE]
					inc		ebx
				.endw
				call	Invalidate
			.elseif eax==IDCANCEL
				invoke EndDialog,hWin,NULL
			.elseif eax==IDC_BTNXD
				.if xp>1
					sub		xp,32
					call	Invalidate
				.endif
			.elseif eax==IDC_BTNXU
				.if xp<512
					add		xp,32
					call	Invalidate
				.endif
			.elseif eax==IDC_BTNYD
				mov		eax,pgain
				.if dword ptr [eax]
					dec		dword ptr [eax]
					call	Invalidate
					inc		sonardata.fGainUpload
				.endif
			.elseif eax==IDC_BTNYU
				mov		eax,pgain
				.if dword ptr [eax]<10000
					inc		dword ptr [eax]
					call	Invalidate
					inc		sonardata.fGainUpload
				.endif
			.endif
		.elseif edx==CBN_SELCHANGE
			.if eax==IDC_CBORANGE
				call	Invalidate
			.endif
		.endif
	.elseif eax==WM_PAINT
		invoke GetClientRect,hWin,addr rect
		invoke BeginPaint,hWin,addr ps
		call	DrawGain
		invoke EndPaint,hWin,addr ps
	.elseif eax==WM_CLOSE
		invoke EndDialog,hWin,NULL
	.else
		mov		eax,FALSE
		ret
	.endif
	mov		eax,TRUE
	ret

Invalidate:
	invoke GetClientRect,hWin,addr rect
	mov		rect.left,GAINXOFS
	mov		eax,rect.left
	add		eax,260
	mov		rect.right,eax
	mov		rect.top,GAINYOFS-1
	mov		eax,rect.top
	add		eax,261
	mov		rect.bottom,eax
	invoke InvalidateRect,hWin,addr rect,TRUE
	inc		sonardata.fGainUpload
	retn

SetupGain:
	invoke SendDlgItemMessage,hWin,IDC_CBORANGE,CB_GETCURSEL,0,0
	mov		ecx,sizeof RANGE
	mul		ecx
	lea		esi,[eax+offset sonardata.sonarrange.gain]
	xor		ebx,ebx
	xor		edi,edi
	.while ebx<16
		;GainVal
		mov		ecx,[esi]
		shl		ecx,13
		;GainInc
		mov		edx,[esi+DWORD]
		sub		edx,[esi]
		shl		edx,8
		push	ebx
		xor		ebx,ebx
		.while ebx<32
			mov		eax,ecx
			shr		eax,13
			.if CARRY?
				inc		eax
			.endif
			add		eax,sonardata.gainofs
			.if eax>4095
				mov		eax,4095
			.endif
			mov		gain[edi],ax
			add		ecx,edx
			lea		edi,[edi+WORD]
			inc		ebx
		.endw
		pop		ebx
		lea		esi,[esi+DWORD]
		inc		ebx
	.endw
	mov		gain[edi],ax
	retn

DrawGain:
	call	SetupGain
	invoke CreatePen,PS_SOLID,1,0FFh
	invoke SelectObject,ps.hdc,eax
	push	eax
	mov		ebx,xp
	shr		ebx,1
	add		ebx,GAINXOFS+1
	invoke MoveToEx,ps.hdc,ebx,GAINYOFS,NULL
	invoke LineTo,ps.hdc,ebx,GAINYOFS+260
	invoke SendDlgItemMessage,hWin,IDC_CBORANGE,CB_GETCURSEL,0,0
	mov		ecx,sizeof RANGE
	mul		ecx
	lea		esi,[eax+offset sonardata.sonarrange.gain]
	lea		eax,[eax+offset sonardata.sonarrange]
	mov		eax,[eax].RANGE.range
	mov		xrange,eax
	mov		eax,xp
	shr		eax,5
	lea		esi,[esi+eax*DWORD]
	mov		pgain,esi
	mov		eax,[esi]
	add		eax,sonardata.gainofs
	.if eax>4095
		mov		eax,4095
	.endif
	mov		yp,eax
	mov		ebx,yp
	shr		ebx,4
	sub		ebx,256
	neg		ebx
	add		ebx,GAINYOFS
	invoke MoveToEx,ps.hdc,GAINXOFS,ebx,NULL
	invoke LineTo,ps.hdc,GAINXOFS+260,ebx
	mov		eax,xrange
	mov		ecx,100
	imul	ecx
	mov		ecx,xp
	imul	ecx
	shr		eax,9
	invoke wsprintf,addr szbuff,addr szFmtDec3,eax
	invoke strlen,addr szbuff
	mov		ecx,dword ptr szbuff[eax-2]
	mov		szbuff[eax-2],'.'
	mov		dword ptr szbuff[eax-1],ecx
	invoke SetDlgItemText,hWin,IDC_STCX,addr szbuff
	invoke SetDlgItemInt,hWin,IDC_STCY,yp,FALSE
	pop		eax
	invoke SelectObject,ps.hdc,eax
	invoke DeleteObject,eax
	invoke CreatePen,PS_SOLID,2,0
	invoke SelectObject,ps.hdc,eax
	push		eax
	;Y-axis
	invoke MoveToEx,ps.hdc,GAINXOFS,GAINYOFS,NULL
	invoke LineTo,ps.hdc,GAINXOFS,GAINYOFS+260
	;X-axis
	invoke MoveToEx,ps.hdc,GAINXOFS,GAINYOFS+260,NULL
	invoke LineTo,ps.hdc,260+GAINXOFS,GAINYOFS+260
	pop		eax
	invoke SelectObject,ps.hdc,eax
	invoke DeleteObject,eax
	invoke CreatePen,PS_SOLID,2,0FF0000h
	invoke SelectObject,ps.hdc,eax
	push	eax
	lea		esi,gain
	xor		ebx,ebx
	.while ebx<MAXYECHO
		movzx	eax,word ptr [esi]
		sub		eax,4095
		neg		eax
		shr		eax,4
		add		eax,GAINYOFS
		mov		edx,ebx
		shr		edx,1
		add		edx,GAINXOFS+1
		.if !ebx
			push	edx
			invoke MoveToEx,ps.hdc,edx,eax,NULL
			pop		edx
		.endif
		lea		esi,[esi+WORD]
		movzx	eax,word ptr [esi]
		sub		eax,4095
		neg		eax
		shr		eax,4
		add		eax,GAINYOFS
		invoke LineTo,ps.hdc,edx,eax
		inc		ebx
	.endw
	pop		eax
	invoke SelectObject,ps.hdc,eax
	invoke DeleteObject,eax
	retn

SonarGainOptionProc endp

SonarColorOptionProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	cc:CHOOSECOLOR
	LOCAL	buffer[256]:BYTE

	mov		eax,uMsg
	.if eax==WM_INITDIALOG
		mov		eax,BST_UNCHECKED
		.if sonardata.fGrayScale
			mov		eax,BST_CHECKED
		.endif
		invoke CheckDlgButton,hWin,IDC_CHKGRAYSCALE,eax
	.elseif eax==WM_COMMAND
		mov		edx,wParam
		movzx	eax,dx
		shr		edx,16
		.if edx==BN_CLICKED
			.if eax==IDOK
				xor		ebx,ebx
				mov		buffer,0
				.while ebx<18
					invoke PutItemInt,addr buffer,sonardata.sonarcolor[ebx*DWORD]
					inc		ebx
				.endw
				invoke PutItemInt,addr buffer,sonardata.fGrayScale
				invoke WritePrivateProfileString,addr szIniSonar,addr szIniSonarColor,addr buffer[1],addr szIniFileName
				invoke EndDialog,hWin,NULL
			.elseif eax==IDC_BTNDEFAULT
				invoke strcpy,addr buffer,addr szDefSonarColors
				xor		ebx,ebx
				.while ebx<18
					invoke GetItemInt,addr buffer,0
					mov		sonardata.sonarcolor[ebx*DWORD],eax
					.if ebx==16
						;Signal bar
						invoke CreatePen,PS_SOLID,1,eax
						push	eax
						invoke SelectObject,sonardata.mDCS,eax
						invoke DeleteObject,eax
						pop		eax
						mov		sonardata.hPen,eax
					.elseif ebx==17
						;Back color
						invoke CreateSolidBrush,eax
						push	eax
						invoke DeleteObject,sonardata.hBrBack
						pop		eax
						mov		sonardata.hBrBack,eax
					.endif
					inc		ebx
				.endw
				invoke InvalidateRect,hWin,NULL,TRUE
			.elseif eax==IDC_CHKGRAYSCALE
				xor		sonardata.fGrayScale,1
			.elseif eax>=1720 && eax<=1737
				push	eax
				lea		ebx,[eax-1720]
				mov		cc.lStructSize,sizeof CHOOSECOLOR
				mov		eax,hWin
				mov		cc.hwndOwner,eax
				mov		eax,hInstance
				mov		cc.hInstance,eax
				mov		cc.lpCustColors,offset CustColors
				mov		cc.Flags,CC_FULLOPEN or CC_RGBINIT
				mov		cc.lCustData,0
				mov		cc.lpfnHook,0
				mov		cc.lpTemplateName,0
				mov		eax,sonardata.sonarcolor[ebx*DWORD]
				mov		cc.rgbResult,eax
				invoke ChooseColor,addr cc
				.if eax
					mov		eax,cc.rgbResult
					mov		sonardata.sonarcolor[ebx*DWORD],eax
					.if ebx==16
						;Signal bar
						invoke CreatePen,PS_SOLID,1,eax
						push	eax
						invoke SelectObject,sonardata.mDCS,eax
						invoke DeleteObject,eax
						pop		eax
						mov		sonardata.hPen,eax
					.elseif ebx==17
						;Back color
						invoke CreateSolidBrush,eax
						push	eax
						invoke DeleteObject,sonardata.hBrBack
						pop		eax
						mov		sonardata.hBrBack,eax
					.endif
				.endif
				pop		eax
				invoke GetDlgItem,hWin,eax
				invoke InvalidateRect,eax,NULL,TRUE
			.endif
		.endif
	.elseif eax==WM_DRAWITEM
		mov		esi,lParam
		mov		eax,wParam
		sub		eax,1720
		mov		eax,sonardata.sonarcolor[eax*DWORD]
		invoke CreateSolidBrush,eax
		push	eax
		invoke FillRect,[esi].DRAWITEMSTRUCT.hdc,addr [esi].DRAWITEMSTRUCT.rcItem,eax
		pop		eax
		invoke DeleteObject,eax
	.elseif eax==WM_CLOSE
		invoke EndDialog,hWin,NULL
	.else
		mov		eax,FALSE
		ret
	.endif
	mov		eax,TRUE
	ret

SonarColorOptionProc endp

Random proc uses ecx edx,range:DWORD

	mov		eax,rseed
	mov		ecx,23
	mul		ecx
	add		eax,7
	and		eax,0FFFFFFFFh
	ror		eax,1
	xor		eax,rseed
	mov		rseed,eax
	mov		ecx,range
	xor		edx,edx
	div		ecx
	mov		eax,edx
	ret

Random endp

GainUpload proc uses ebx edi

	;Setup gain array
	movzx	ebx,sonardata.RangeInx
	invoke GetRangePtr,ebx
	mov		ebx,eax
	;Fixed gain
	mov		eax,sonardata.GainSet
	mov		sonardata.GainInit[0],ax
	xor		ecx,ecx
	xor		edi,edi
	.if sonardata.AutoGain
		;Time dependent gain
		.while ecx<17
			mov		eax,sonardata.sonarrange.gain[ebx+ecx*DWORD]
			lea		edi,[edi+1]
			mov		sonardata.GainInit[edi*WORD],ax
			lea		ecx,[ecx+1]
		.endw
	.else
		;Fixed gain
		xor		eax,eax
		.while ecx<17
			lea		edi,[edi+1]
			mov		sonardata.GainInit[edi*WORD],ax
			lea		ecx,[ecx+1]
		.endw
	.endif
	;Upload Gain array
	invoke STLinkWrite,hSonar,STM32_Sonar+16+sizeof SONAR.EchoArray+sizeof SONAR.GainArray,addr sonardata.GainInit,sizeof SONAR.GainInit
	ret

GainUpload endp

STMThread proc uses ebx esi edi,Param:DWORD
	LOCAL	status:DWORD
	LOCAL	dwread:DWORD
	LOCAL	dwwrite:DWORD
	LOCAL	buffer[16]:BYTE
	LOCAL	pixcnt:DWORD
	LOCAL	pixdir:DWORD
	LOCAL	pixmov:DWORD
	LOCAL	pixdpt:DWORD
	LOCAL	rngchanged:DWORD
	LOCAL	rngdecrement:DWORD
	LOCAL	iLon:DWORD
	LOCAL	iLat:DWORD
	LOCAL	fDist:REAL10
	LOCAL	fBear:REAL10
	LOCAL	iSumDist:DWORD
	LOCAL	ft:FILETIME
	LOCAL	lft:FILETIME
	LOCAL	lst:SYSTEMTIME

	mov		pixcnt,0
	mov		pixdir,0
	mov		pixmov,0
	mov		pixdpt,250
	mov		rngchanged,4
	mov		mapdata.ntrail,0
	mov		iLat,-1
	mov		iLon,-1
	invoke RtlZeroMemory,addr STM32Echo,sizeof STM32Echo
	invoke DoSleep,2000
	.while !fExitSTMThread
		invoke IsDlgButtonChecked,hWnd,IDC_CHKCHART
		.if eax
			.if sonardata.fSTLink && sonardata.fSTLink!=IDIGNORE
				;Download Start status (first byte)
				invoke STLinkRead,hSonar,STM32_Sonar,addr status,4
				.if !eax || eax==IDABORT || eax==IDIGNORE
					jmp		STLinkErr
				.endif
				.if !(status & 255)
					;Download ADCBattery, ADCWaterTemp, ADCAirTemp and GPSHead
					invoke STLinkRead,hSonar,STM32_Sonar+8,addr sonardata.ADCBattery,8
					.if !eax || eax==IDABORT || eax==IDIGNORE
						jmp		STLinkErr
					.endif
				 	;Upload Start and PingPulses
					mov		eax,sonardata.PingInit
					.if sonardata.AutoPing
						add		eax,sonardata.sonarrange.pingadd[ebx]
						.if eax>MAXPING
							mov		eax,MAXPING
						.endif
					.endif
					mov		sonardata.PingPulses,al
					;Start the next reading
				 	mov		sonardata.Start,4
					invoke STLinkWrite,hSonar,STM32_Sonar,addr sonardata.Start,4
					.if !eax || eax==IDABORT || eax==IDIGNORE
						jmp		STLinkErr
					.endif
					invoke SonarUpdateProc,0
				.endif
			.endif
			invoke DoSleep,100
			.if sonardata.PaintNow
				mov		sonardata.PaintNow,0
				invoke InvalidateRect,hSonar,NULL,TRUE
				invoke UpdateWindow,hSonar
			.endif
		.else
			.if sonardata.hReplay
				;Replay mode
				mov		sonardata.fReplayRead,TRUE
				;Copy old echo
				call	MoveEcho
				;Read echo from file
				.if sonarreplay.Version>=200
					invoke ReadFile,sonardata.hReplay,addr sonarreplay,sizeof SONARREPLAY,addr dwread,NULL
					.if dwread==sizeof SONARREPLAY
						.if sonarreplay.Version==201
							invoke ReadFile,sonardata.hReplay,addr satelites,sizeof SATELITE*12,addr dwread,NULL
							invoke ReadFile,sonardata.hReplay,addr altitude,sizeof ALTITUDE,addr dwread,NULL
						.endif
						invoke ReadFile,sonardata.hReplay,addr STM32Echo,MAXYECHO,addr dwread,NULL
						mov		eax,mapdata.iLon
						mov		iLon,eax
						mov		eax,mapdata.iLat
						mov		iLat,eax
						mov		mapdata.fcursor,2
						movzx	eax,sonarreplay.SoundSpeed
						mov		sonardata.SoundSpeed,eax
						mov		ax,sonarreplay.ADCBattery
						mov		sonardata.ADCBattery,ax
						mov		ax,sonarreplay.ADCWaterTemp
						mov		sonardata.ADCWaterTemp,ax
						mov		ax,sonarreplay.ADCAirTemp
						mov		sonardata.ADCAirTemp,ax
						mov		eax,sonarreplay.iTime
						mov		mapdata.iTime,eax
						mov		ecx,eax
						movzx	edx,ax
						shr		ecx,16
						invoke DosDateTimeToFileTime,ecx,edx,addr ft
						invoke FileTimeToLocalFileTime,addr ft,addr lft
						invoke FileTimeToSystemTime,addr lft,addr lst
						movzx	eax,lst.wSecond
						push	eax
						movzx	eax,lst.wMinute
						push	eax
						movzx	eax,lst.wHour
						push	eax
						movzx	eax,lst.wYear
						sub		eax,1980
						push	eax
						movzx	eax,lst.wMonth
						push	eax
						movzx	eax,lst.wDay
						push	eax
						invoke wsprintf,addr mapdata.options.text[sizeof OPTIONS*4],offset szFmtTime
						mov		eax,sonarreplay.iLon
						mov		mapdata.iLon,eax
						mov		eax,sonarreplay.iLat
						mov		mapdata.iLat,eax
						movzx	eax,sonarreplay.iSpeed
						mov		mapdata.iSpeed,eax
						movzx	eax,sonarreplay.iBear
						mov		mapdata.iBear,eax
						invoke SetGPSCursor
						mov		eax,mapdata.iLon
						mov		edx,mapdata.iLat
						.if eax!=iLon || edx!=iLat
							invoke DoGoto,mapdata.iLon,mapdata.iLat,mapdata.gpslock,TRUE
							invoke SetDlgItemInt,hWnd,IDC_EDTEAST,mapdata.iLon,TRUE
							invoke SetDlgItemInt,hWnd,IDC_EDTNORTH,mapdata.iLat,TRUE
							movzx	eax,sonarreplay.iSpeed
							mov		mapdata.iSpeed,eax
							invoke wsprintf,addr buffer,addr szFmtDec2,eax
							invoke strlen,addr buffer
							movzx	ecx,word ptr buffer[eax-1]
							shl		ecx,8
							mov		cl,'.'
							mov		dword ptr buffer[eax-1],ecx
							invoke strcpy,addr mapdata.options.text,addr buffer
							invoke AddTrailPoint,mapdata.iLon,mapdata.iLat,mapdata.iBear,mapdata.iTime,mapdata.iSpeed
							.if mapdata.ntrail
								mov		eax,mapdata.iLon
								mov		edx,mapdata.iLat
								.if eax!=iLon || edx!=iLat
									invoke BearingDistanceInt,iLon,iLat,mapdata.iLon,mapdata.iLat,addr fDist,addr fBear
									fld		fDist
									fld		mapdata.fSumDist
									faddp	st(1),st(0)
									fst		st(1)
									lea		eax,mapdata.fSumDist
									fstp	REAL10 PTR [eax]
									lea		eax,iSumDist
									fistp	dword ptr [eax]
									invoke SetDlgItemInt,hWnd,IDC_EDTDIST,iSumDist,FALSE
									invoke SetDlgItemInt,hWnd,IDC_EDTBEAR,mapdata.iBear,FALSE
								.endif
							.endif
							inc		mapdata.ntrail
							inc		mapdata.paintnow
							invoke InvalidateRect,hGPS,NULL,TRUE
						.endif
					.endif
				.else
					invoke ReadFile,sonardata.hReplay,addr STM32Echo,MAXYECHO,addr dwread,NULL
				.endif
				.if dwread!=MAXYECHO
					mov		sonardata.fReplayRead,FALSE
					invoke CloseHandle,sonardata.hReplay
					mov		sonardata.hReplay,0
					invoke SetScrollPos,hSonar,SB_HORZ,0,TRUE
					mov		sonardata.dptinx,0
					invoke EnableScrollBar,hSonar,SB_HORZ,ESB_DISABLE_BOTH
					mov		mapdata.ntrail,0
					mov		iLat,-1
					mov		iLon,-1
					mov		mapdata.trailhead,0
					mov		mapdata.trailtail,0
					inc		mapdata.paintnow
					fldz
					fstp	mapdata.fSumDist
					invoke SetDlgItemText,hWnd,IDC_EDTDIST,addr szNULL
				.else
					invoke GetScrollPos,hSonar,SB_HORZ
					inc		eax
					invoke SetScrollPos,hSonar,SB_HORZ,eax,TRUE
					mov		sonardata.fReplayRead,FALSE
					movzx	eax,STM32Echo
					.if al!=STM32Echo[MAXYECHO]
						mov		sonardata.dptinx,0
						mov		rngchanged,4
					.endif
					invoke SetRange,eax
					call	ShowEcho
				.endif
			.elseif sonardata.fSTLink && sonardata.fSTLink!=IDIGNORE
				;Sonar mode
				.if mapdata.GPSInit
					mov		mapdata.GPSInit,2
					.while mapdata.GPSInit
						invoke DoSleep,100
					.endw
				.endif
				;Download Start status (first byte)
				invoke STLinkRead,hSonar,STM32_Sonar,addr status,4
				.if !eax || eax==IDABORT || eax==IDIGNORE
					jmp		STLinkErr
				.endif
				.if !(status & 255)
					;Download ADCBattery, ADCWaterTemp, ADCAirTemp and GPSHead
					invoke STLinkRead,hSonar,STM32_Sonar+8,addr sonardata.ADCBattery,8
					.if !eax || eax==IDABORT || eax==IDIGNORE
						jmp		STLinkErr
					.endif
					;Copy old echo
					call	MoveEcho
					;Download sonar echo array
					invoke STLinkRead,hSonar,STM32_Sonar+16,addr STM32Echo,MAXYECHO
					.if !eax || eax==IDABORT || eax==IDIGNORE
						jmp		STLinkErr
					.endif
					movzx	ebx,sonardata.RangeInx
					invoke GetRangePtr,ebx
					mov		ebx,eax
					.if sonardata.fGainUpload
						;Upload Gain array
						dec		sonardata.fGainUpload
						invoke GainUpload
					.endif
				 	;Upload Start, PingPulses, PingTimer, RangeInx, PixelTimer and PingWait to init the next reading
					mov		eax,sonardata.PingInit
					.if sonardata.AutoPing
						add		eax,sonardata.sonarrange.pingadd[ebx]
						.if eax>MAXPING
							mov		eax,MAXPING
						.endif
					.endif
					mov		sonardata.PingPulses,al
					mov		sonardata.PingWait,6
					mov		sonardata.PingWait,6
				 	mov		sonardata.Start,0
					invoke STLinkWrite,hSonar,STM32_Sonar,addr sonardata.Start,8
					.if !eax || eax==IDABORT || eax==IDIGNORE
						jmp		STLinkErr
					.endif
					;Start the next phase
				 	mov		sonardata.Start,1
					invoke STLinkWrite,hSonar,STM32_Sonar,addr sonardata.Start,4
					.if !eax || eax==IDABORT || eax==IDIGNORE
						jmp		STLinkErr
					.endif
					call	ShowEcho
				.else
					;Data not ready yet
					invoke Sleep,10
					.if sonardata.PaintNow
						mov		sonardata.PaintNow,0
						invoke InvalidateRect,hSonar,NULL,TRUE
						invoke UpdateWindow,hSonar
					.endif
				.endif
			.elseif sonardata.fSTLink==IDIGNORE
				;Random demo mode
				;Copy old echo
				call	MoveEcho
				;Clear echo
				xor		eax,eax
				lea		edi,STM32Echo
				mov		ecx,MAXYECHO/4
				rep		stosd
				;Set range index
				movzx	eax,sonardata.RangeInx
				mov		STM32Echo,al
				;Show ping
				invoke GetRangePtr,eax
				mov		eax,sonardata.sonarrange.pixeltimer[eax]
				mov		ecx,sonardata.sonarrange.pixeltimer
				xor		edx,edx
				div		ecx
				mov		ecx,eax
				mov		eax,100
				xor		edx,edx
				div		ecx
				.if eax<3
					mov		eax,3
				.endif
				push	eax
				mov		edi,eax
				mov		edx,1
				.while edx<edi
					invoke Random,50
					add		eax,255-50
					mov		STM32Echo[edx],al
					inc		edx
				.endw
				;Show surface clutter
				invoke Random,edi
				mov		ecx,edi
				add		ecx,eax
				.while edx<ecx
					invoke Random,255
					mov		STM32Echo[edx],al
					inc		edx
				.endw
				.if !(pixcnt & 63)
					;Random direction
					invoke Random,10
					mov		pixdir,eax
				.endif
				.if !(pixcnt & 7)
					;Random move
					invoke Random,5
					mov		pixmov,eax
				.endif
				mov		ebx,pixdpt
				mov		eax,pixdir
				.if eax<=1 && ebx>100
					;Up
					sub		ebx,pixmov
				.elseif eax>=3 && ebx<15000
					;Down
					add		ebx,pixmov
				.endif
				mov		pixdpt,ebx
				inc		pixcnt
				mov		eax,ebx
				mov		ecx,1024
				mul		ecx
				push	eax
				;Get current range index
				movzx	eax,STM32Echo
				invoke GetRangePtr,eax
				mov		ecx,sonardata.sonarrange.range[eax]
				pop		eax
				xor		edx,edx
				div		ecx
				mov		ecx,100
				xor		edx,edx
				div		ecx
				mov		ebx,eax
				invoke Random,edi
				mov		edx,eax
				sub		ebx,eax
				.if sdword ptr ebx<=0
					mov		ebx,1
				.endif
				.while edx && ebx<MAXYECHO
					;Random bottom vegetation
					invoke Random,64
					add		eax,32
					mov		STM32Echo[ebx],al
					inc		ebx
					dec		edx
				.endw
				pop		edx
				push	ebx
				shl		edx,2
				xor		ecx,ecx
				.while ecx<edx && ebx<MAXYECHO
					;Random bottom echo
					invoke Random,48
					add		eax,255-48
					sub		eax,ecx
					mov		STM32Echo[ebx],al
					inc		ebx
					inc		ecx
				.endw
				mov		eax,edx
				shl		edx,2
				invoke Random,eax
				add		edx,eax
				.if edx>255
					mov		edx,255
				.endif
				xor		ecx,ecx
				.while ecx<edx && ebx<MAXYECHO
					;Random bottom weak echo
					mov		eax,ecx
					xor		eax,0FFh
					.if !eax
						inc		eax
					.endif
					invoke Random,eax
					mov		STM32Echo[ebx],al
					inc		ebx
					inc		ecx
				.endw
				pop		ebx
				invoke Random,ebx
				.if eax>100 && eax<MAXYECHO-1
					mov		edx,eax
					invoke Random,255
					.if eax>124 && eax<130
						;Random fish
						mov		ah,al
						mov		word ptr STM32Echo[edx],ax
						mov		word ptr STM32Echo[edx+MAXYECHO],ax
						mov		word ptr STM32Echo[edx+MAXYECHO*2],ax
					.endif
				.endif
				mov		sonardata.ADCBattery,08F0h
				mov		sonardata.ADCWaterTemp,04A0h
				mov		sonardata.ADCAirTemp,0620h
				call	ShowEcho
			.endif
		.endif
	.endw
	mov		fExitSTMThread,2
	xor		eax,eax
	ret

STLinkErr:
	invoke PostMessage,hWnd,WM_CLOSE,0,0
	xor		eax,eax
	ret

ShowEcho:
	.if sonardata.hLog
		;Write to log file
		mov		sonarreplay.Version,201
		mov		al,sonardata.PingPulses
		mov		sonarreplay.PingPulses,al
		mov		eax,sonardata.GainSet
		mov		sonarreplay.GainSet,ax
		mov		eax,sonardata.SoundSpeed
		mov		sonarreplay.SoundSpeed,ax
		mov		ax,sonardata.ADCBattery
		mov		sonarreplay.ADCBattery,ax
		mov		ax,sonardata.ADCWaterTemp
		mov		sonarreplay.ADCWaterTemp,ax
		mov		ax,sonardata.ADCAirTemp
		mov		sonarreplay.ADCAirTemp,ax
		mov		eax,mapdata.iTime
		mov		sonarreplay.iTime,eax
		mov		eax,mapdata.iLon
		mov		sonarreplay.iLon,eax
		mov		eax,mapdata.iLat
		mov		sonarreplay.iLat,eax
		mov		eax,mapdata.iSpeed
		mov		sonarreplay.iSpeed,ax
		mov		eax,mapdata.iBear
		mov		sonarreplay.iBear,ax
		invoke WriteFile,sonardata.hLog,addr sonarreplay,sizeof SONARREPLAY,addr dwwrite,NULL
		invoke WriteFile,sonardata.hLog,addr satelites,sizeof satelites,addr dwwrite,NULL
		invoke WriteFile,sonardata.hLog,addr altitude,sizeof altitude,addr dwwrite,NULL
		invoke WriteFile,sonardata.hLog,addr STM32Echo,MAXYECHO,addr dwwrite,NULL
	.endif
	movzx	eax,STM32Echo
	.if al!=STM32Echo[MAXYECHO]
		call	CopyEcho
	.endif
	.if rngchanged
		call	FindDepth
		dec		rngchanged
		call	DrawEcho
	.else
		call	FindDepth
		call	FindFish
		call	DrawEcho
		call	TestRangeChange
	.endif
	retn

DrawEcho:
	;Get current range index
	movzx	eax,STM32Echo
	mov		sonardata.EchoArray,al
	invoke GetRangePtr,eax
	mov		eax,sonardata.sonarrange.interval[eax]
	.if sonardata.hReplay!=0 || sonardata.fSTLink==IDIGNORE
		mov		ecx,REPLAYSPEED
		xor		edx,edx
		div		ecx
	.endif
	mov		esi,sonardata.ChartSpeed
	xor		edx,edx
	div		esi
	mov		edi,eax
	.if esi==1
		call	Show0
	.elseif esi==2
		call	Show50
		call	Show0
	.elseif esi==3
		call	Show66
		call	Show33
		call	Show0
	.else
		call	Show75
		call	Show50
		call	Show25
		call	Show0
	.endif
	retn

MoveEcho:
	;Move echo arrays
	invoke RtlMoveMemory,addr STM32Echo[MAXYECHO*3],addr STM32Echo[MAXYECHO*2],MAXYECHO
	invoke RtlMoveMemory,addr STM32Echo[MAXYECHO*2],addr STM32Echo[MAXYECHO*1],MAXYECHO
	invoke RtlMoveMemory,addr STM32Echo[MAXYECHO*1],addr STM32Echo[MAXYECHO*0],MAXYECHO
	retn

CopyEcho:
	;Copy echo arrays
	invoke RtlMoveMemory,addr STM32Echo[MAXYECHO*3],addr STM32Echo,MAXYECHO
	invoke RtlMoveMemory,addr STM32Echo[MAXYECHO*2],addr STM32Echo,MAXYECHO
	invoke RtlMoveMemory,addr STM32Echo[MAXYECHO*1],addr STM32Echo,MAXYECHO
	retn

FindDepth:
	mov		eax,sonardata.dptinx
	mov		sonardata.prvdptinx,eax
;	;Skip blank
;	mov		ebx,1
;	mov		ecx,sonardata.NoiseLevel
;	.while ebx<32
;		mov		ax,word ptr STM32Echo[ebx]
;		.break .if al>=cl && ah>cl
;		inc		ebx
;	.endw
	;Skip ping and surface clutter
	movzx	eax,STM32Echo
	invoke GetRangePtr,eax
	mov		ebx,sonardata.sonarrange.mindepth[eax]
	.while ebx<MAXYECHO/2
		xor		ch,ch
		mov		ax,word ptr STM32Echo[ebx+MAXYECHO*0]
		mov		dx,word ptr STM32Echo[ebx+MAXYECHO*0+2]
		.if al<cl && ah<cl && dl<cl && dh<cl
			inc		ch
		.endif
		mov		ax,word ptr STM32Echo[ebx+MAXYECHO*1]
		mov		dx,word ptr STM32Echo[ebx+MAXYECHO*1+2]
		.if al<cl && ah<cl && dl<cl && dh<cl
			inc		ch
		.endif
		mov		ax,word ptr STM32Echo[ebx+MAXYECHO*2]
		mov		dx,word ptr STM32Echo[ebx+MAXYECHO*2+2]
		.if al<cl && ah<cl && dl<cl && dh<cl
			inc		ch
		.endif
		mov		ax,word ptr STM32Echo[ebx+MAXYECHO*3]
		mov		dx,word ptr STM32Echo[ebx+MAXYECHO*3+2]
		.if al<cl && ah<cl && dl<cl && dh<cl
			inc		ch
		.endif
		.break .if ch==4
		inc		ebx
	.endw
	mov		sonardata.minyecho,ebx
	xor		esi,esi
	xor		edi,edi
	.if ch==4
		;Find the strongest echo in a 4x16 sqare
		.while ebx<MAXYECHO
			xor		ecx,ecx
			xor		edx,edx
			.while ecx<16
				lea		eax,[ebx+ecx]
				.break .if eax>=MAXYECHO
				movzx	eax,STM32Echo[ebx+ecx+MAXYECHO*0]
				add		edx,eax
				movzx	eax,STM32Echo[ebx+ecx+MAXYECHO*1]
				add		edx,eax
				movzx	eax,STM32Echo[ebx+ecx+MAXYECHO*2]
				add		edx,eax
				movzx	eax,STM32Echo[ebx+ecx+MAXYECHO*3]
				add		edx,eax
				inc		ecx
			.endw
			;Put in a little hysteresis
			lea		eax,[edx-DEPTHHYSTERESIS]
			.if sdword ptr eax>esi
				mov		esi,edx
				mov		edi,ebx
			.endif
			inc		ebx
		.endw
	.endif
	.if edi>10
		;A valid bottom signal has been found
		mov		sonardata.nodptinx,0
		mov		eax,sonardata.dptinx
		.if eax
			sub		eax,edi
			mov		edx,eax
			.if CARRY?
				neg		edx
			.endif
			.if edx<MAXDEPTHJUMP
				.if sdword ptr eax>2
					mov		edi,sonardata.dptinx
					sub		edi,2
				.elseif sdword ptr eax<-2
					mov		edi,sonardata.dptinx
					add		edi,2
				.endif
			.else
				.if sdword ptr eax>MAXDEPTHJUMP
					mov		edi,sonardata.dptinx
					sub		edi,MAXDEPTHJUMP
				.elseif sdword ptr eax<-MAXDEPTHJUMP
					mov		edi,sonardata.dptinx
					add		edi,MAXDEPTHJUMP
				.endif
				mov		sonardata.nodptinx,1
			.endif
		.endif
		mov		ebx,edi
		mov		sonardata.dptinx,ebx
		call	CalculateDepth
		call	SetDepth
		or		sonardata.ShowDepth,2
	.else
		and		sonardata.ShowDepth,1
		inc		sonardata.nodptinx
	.endif
	retn

CalculateDepth:
	push	ecx
	push	edx
	movzx	eax,STM32Echo
	invoke GetRangePtr,eax
	mov		eax,sonardata.sonarrange.range[eax]
	mov		ecx,10
	mul		ecx
	mul		ebx
	mov		ecx,MAXYECHO
	div		ecx
	pop		edx
	pop		ecx
	retn

SetDepth:
	invoke wsprintf,addr buffer,addr szFmtDec2,eax
	invoke strlen,addr buffer
	.if eax>3
		;Remove the decimal
		mov		byte ptr buffer[eax-1],0
	.else
		;Add a decimal point
		movzx	ecx,word ptr buffer[eax-1]
		shl		ecx,8
		mov		cl,'.'
		mov		dword ptr buffer[eax-1],ecx
	.endif
	invoke strcpy,addr sonardata.options.text[1*sizeof OPTIONS],addr buffer
	retn

ScrollFish:
	mov		esi,offset sonardata.fishdata
	mov		ecx,MAXFISH
	.while ecx
		dec		[esi].FISH.xpos
		lea		esi,[esi+sizeof FISH]
		dec		ecx
	.endw
	retn

CheckFish:
	push	esi
	push	edi
	mov		edi,MAXFISH
	mov		esi,offset sonardata.fishdata
	.while edi
		.if sdword ptr [esi].FISH.xpos>MAXXECHO-16
			.if sdword ptr [esi].FISH.depth>ecx && sdword ptr [esi].FISH.depth<edx
				;The detected fish is close to a previously detected fish, ignore it
				xor		eax,eax
				.break
			.endif
		.endif
		dec		edi
		lea		esi,[esi+sizeof FISH]
	.endw
	pop		edx
	pop		esi
	retn

FindFish:
	.if sonardata.FishDetect || sonardata.FishAlarm
		mov		ebx,sonardata.minyecho
		mov		edi,sonardata.dptinx
		.if !edi
			;Depth unknowm
			retn
		.elseif edi>sonardata.minyecho
			;Skip bottom vegetation
			mov		ecx,sonardata.NoiseLevel
			.while edi>ebx
				dec		edi
				mov		ax,word ptr STM32Echo[edi]
				mov		dx,word ptr STM32Echo[edi+MAXYECHO]
				.if al<cl && ah<cl && dl<cl && dh<cl
					inc		ch
				.else
					xor		ch,ch
				.endif
				.break .if ch==5
			.endw
		.else
			;Too shallow
			retn
		.endif
		.while ebx<edi
			mov		ax,word ptr STM32Echo[ebx]
			;2x3
			mov		dx,word ptr STM32Echo[ebx+MAXYECHO]
			mov		cx,word ptr STM32Echo[ebx+MAXYECHO*2]
			.if sonardata.FishDetect==2
				;2x2
				mov		cx,ax
			.elseif sonardata.FishDetect==3
				;2x1
				mov		dx,ax
				mov		cx,ax
			.endif
			.if al>=SMALLFISHECHO && ah>=SMALLFISHECHO && dl>=SMALLFISHECHO && dh>=SMALLFISHECHO && cl>=SMALLFISHECHO && ch>=SMALLFISHECHO
				.if sonardata.FishDetect
					mov		eax,sonardata.fishinx
					mov		ecx,sizeof FISH
					mul		ecx
					mov		esi,eax
					movzx	eax,STM32Echo
					invoke GetRangePtr,eax
					mov		edx,sonardata.sonarrange.range[eax]
					shr		edx,1
					call	CalculateDepth
					mov		ecx,eax
					sub		ecx,edx
					lea		edx,[eax+edx]
					call	CheckFish
					.if eax
						movzx	edx,STM32Echo[ebx]
						.if edx>=LARGEFISHECHO
							;Large fish
							mov		edx,18+8
						.else
							;Small fish
							mov		edx,17+8
						.endif
						;Update the fishdata array
						mov		sonardata.fishdata.fishtype[esi],edx
						mov		sonardata.fishdata.xpos[esi],511
						mov		sonardata.fishdata.depth[esi],eax
						;Increment the fishdata index
						mov		eax,sonardata.fishinx
						inc		eax
						.if eax==MAXFISH
							xor		eax,eax
						.endif
						mov		sonardata.fishinx,eax
					.endif
				.endif
				.if sonardata.FishAlarm && !sonardata.fFishSound
					;Play a wav file
					mov		sonardata.fFishSound,3
					invoke PlaySound,addr sonardata.szFishSound,hInstance,SND_ASYNC
				.endif
				.break
			.endif
			inc		ebx
		.endw
	.endif
	retn

TestRangeChange:
	.if sonardata.AutoRange && !sonardata.hReplay
		movzx	eax,STM32Echo
		mov		edx,sonardata.MaxRange
		dec		edx
		mov		ebx,sonardata.dptinx
		.if sonardata.nodptinx
			;Bottom not found
			.if sonardata.nodptinx>=10
				mov		sonardata.nodptinx,0
				.if rngdecrement
					.if eax
						;Range decrement
						dec		eax
						invoke SetRange,eax
						mov		rngchanged,8
						mov		sonardata.dptinx,0
						inc		sonardata.fGainUpload
					.else
						mov		rngdecrement,FALSE
					.endif
				.else
					.if eax<edx
						;Range increment
						inc		eax
						invoke SetRange,eax
						mov		rngchanged,8
						mov		sonardata.dptinx,0
						inc		sonardata.fGainUpload
					.else
						mov		rngdecrement,TRUE
					.endif
				.endif
			.endif
		.else
			mov		rngdecrement,FALSE
			;Check if range should be changed
			.if eax && ebx<MAXYECHO/3
				;Range decrement
				dec		eax
				invoke SetRange,eax
				mov		rngchanged,10
				mov		sonardata.dptinx,0
				inc		sonardata.fGainUpload
			.elseif eax<edx && ebx>(MAXYECHO-MAXYECHO/5)
				;Range increment
				inc		eax
				invoke SetRange,eax
				mov		rngchanged,10
				mov		sonardata.dptinx,0
				inc		sonardata.fGainUpload
			.endif
		.endif
	.endif
	retn

Show0:
	mov		esi,1
	mov		eax,sonardata.NoiseReject
	mov		ebx,sonardata.NoiseLevel
	.if eax==1
		;1*2
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			mov		ah,STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl)
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.elseif eax==2
		;2*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl || dl<bl || dh<bl)
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.elseif eax==3
		;3*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			mov		cx,word ptr STM32Echo[esi+MAXYECHO*2]
			.if (al<bl || ah<bl || dl<bl || dh<bl || cl<bl || ch<bl)
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.else
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			.if al<bl
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.endif
	push	edi
	call	ScrollFish
	invoke SonarUpdateProc,1
	pop		edi
	invoke DoSleep,edi
	retn

Show25:
	mov		esi,1
	mov		eax,sonardata.NoiseReject
	mov		ebx,sonardata.NoiseLevel
	.if eax==1
		;1*2
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			mov		ah,STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl)
				mov		al,0
			.else
				;Blend in 25% of previous echo
				movzx	edx,ah
				movzx	eax,al
				shl		eax,2
				add		eax,edx
				mov		ecx,5
				xor		edx,edx
				div		ecx
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.elseif eax==2
		;2*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl || dl<bl || dh<bl) 
				mov		al,0
			.else
				;Blend in 25% of previous echo
				movzx	edx,dl
				movzx	eax,al
				shl		eax,2
				add		eax,edx
				mov		ecx,5
				xor		edx,edx
				div		ecx
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.elseif eax==3
		;3*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			mov		cx,word ptr STM32Echo[esi+MAXYECHO*2]
			.if (al<bl || ah<bl || dl<bl || dh<bl || cl<bl || ch<bl) 
				mov		al,0
			.else
				;Blend in 25% of previous echo
				movzx	edx,dl
				movzx	eax,al
				shl		eax,2
				add		eax,edx
				mov		ecx,5
				xor		edx,edx
				div		ecx
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.else
		.while esi<MAXYECHO
			;Blend in 25% of previous echo
			movzx	eax,STM32Echo[esi]
			shl		eax,2
			movzx	edx,STM32Echo[esi+MAXYECHO]
			add		eax,edx
			mov		ecx,5
			xor		edx,edx
			div		ecx
			.if al<bl
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.endif
	call	ScrollFish
	invoke SonarUpdateProc,1
	invoke DoSleep,edi
	retn

Show33:
	mov		esi,1
	mov		eax,sonardata.NoiseReject
	mov		ebx,sonardata.NoiseLevel
	.if eax==1
		;1*2
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			mov		ah,STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl)
				mov		al,0
			.else
				;Blend in 33% of previous echo
				movzx	eax,ah
				mov		ecx,3
				xor		edx,edx
				div		ecx
				mov		edx,eax
				movzx	eax,STM32Echo[esi]
				add		eax,edx
				mov		ecx,3
				mul		ecx
				shr		eax,2
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.elseif eax==2
		;2*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl || dl<bl || dh<bl) 
				mov		al,0
			.else
				;Blend in 33% of previous echo
				movzx	eax,dl
				mov		ecx,3
				xor		edx,edx
				div		ecx
				mov		edx,eax
				movzx	eax,STM32Echo[esi]
				add		eax,edx
				mov		ecx,3
				mul		ecx
				shr		eax,2
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.elseif eax==3
		;3*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			mov		cx,word ptr STM32Echo[esi+MAXYECHO*2]
			.if (al<bl || ah<bl || dl<bl || dh<bl || cl<bl || ch<bl) 
				mov		al,0
			.else
				;Blend in 33% of previous echo
				movzx	eax,dl
				mov		ecx,3
				xor		edx,edx
				div		ecx
				mov		edx,eax
				movzx	eax,STM32Echo[esi]
				add		eax,edx
				mov		ecx,3
				mul		ecx
				shr		eax,2
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.else
		.while esi<MAXYECHO
			;Blend in 33% of previous echo
			movzx	eax,STM32Echo[esi+MAXYECHO]
			mov		ecx,3
			xor		edx,edx
			div		ecx
			mov		edx,eax
			movzx	eax,STM32Echo[esi]
			add		eax,edx
			mov		ecx,3
			mul		ecx
			shr		eax,2
			.if al<bl
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.endif
	call	ScrollFish
	invoke SonarUpdateProc,1
	invoke DoSleep,edi
	retn

Show50:
	mov		esi,1
	mov		eax,sonardata.NoiseReject
	mov		ebx,sonardata.NoiseLevel
	.if eax==1
		;1*2
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			mov		ah,STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl)
				mov		al,0
			.else
				;Blend in 50% of previous echo
				movzx	edx,ah
				movzx	eax,al
				add		eax,edx
				shr		eax,1
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.elseif eax==2
		;2*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl || dl<bl || dh<bl) 
				mov		al,0
			.else
				;Blend in 50% of previous echo
				movzx	edx,dl
				movzx	eax,al
				add		eax,edx
				shr		eax,1
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.elseif eax==3
		;3*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			mov		cx,word ptr STM32Echo[esi+MAXYECHO*2]
			.if (al<bl || ah<bl || dl<bl || dh<bl || cl<bl || ch<bl) 
				mov		al,0
			.else
				;Blend in 50% of previous echo
				movzx	edx,dl
				movzx	eax,al
				add		eax,edx
				shr		eax,1
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.else
		.while esi<MAXYECHO
			;Blend in 50% of previous echo
			movzx	eax,STM32Echo[esi]
			movzx	edx,STM32Echo[esi+MAXYECHO]
			add		eax,edx
			shr		eax,1
			.if al<bl
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.endif
	call	ScrollFish
	invoke SonarUpdateProc,1
	invoke DoSleep,edi
	retn

Show66:
	mov		esi,1
	mov		eax,sonardata.NoiseReject
	mov		ebx,sonardata.NoiseLevel
	.if eax==1
		;1*2
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			mov		ah,STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl)
				mov		al,0
			.else
				;Blend in 66% of previous echo
				movzx	eax,al
				mov		ecx,3
				xor		edx,edx
				div		ecx
				mov		edx,eax
				movzx	eax,STM32Echo[esi+MAXYECHO]
				add		eax,edx
				mov		ecx,3
				mul		ecx
				shr		eax,2
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.elseif eax==2
		;2*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl || dl<bl || dh<bl) 
				mov		al,0
			.else
				;Blend in 66% of previous echo
				movzx	eax,al
				mov		ecx,3
				xor		edx,edx
				div		ecx
				mov		edx,eax
				movzx	eax,STM32Echo[esi+MAXYECHO]
				add		eax,edx
				mov		ecx,3
				mul		ecx
				shr		eax,2
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.elseif eax==3
		;3*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			mov		cx,word ptr STM32Echo[esi+MAXYECHO*2]
			.if (al<bl || ah<bl || dl<bl || dh<bl || cl<bl || ch<bl) 
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.else
		.while esi<MAXYECHO
			;Blend in 66% of previous echo
			movzx	eax,STM32Echo[esi]
			mov		ecx,3
			xor		edx,edx
			div		ecx
			mov		edx,eax
			movzx	eax,STM32Echo[esi+MAXYECHO]
			add		eax,edx
			mov		ecx,3
			mul		ecx
			shr		eax,2
			.if al<bl
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.endif
	call	ScrollFish
	invoke SonarUpdateProc,1
	invoke DoSleep,edi
	retn

Show75:
	mov		esi,1
	mov		eax,sonardata.NoiseReject
	mov		ebx,sonardata.NoiseLevel
	.if eax==1
		;1*2
		.while esi<MAXYECHO
			mov		al,STM32Echo[esi]
			mov		ah,STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl)
				mov		al,0
			.else
				;Blend in 75% of previous echo
				movzx	edx,al
				movzx	eax,ah
				shl		eax,2
				add		eax,edx
				mov		ecx,5
				xor		edx,edx
				div		ecx
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.elseif eax==2
		;2*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			.if (al<bl || ah<bl || dl<bl || dh<bl) 
				mov		al,0
			.else
				;Blend in 75% of previous echo
				movzx	edx,al
				movzx	eax,STM32Echo[esi+MAXYECHO]
				shl		eax,2
				add		eax,edx
				mov		ecx,5
				xor		edx,edx
				div		ecx
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.elseif eax==3
		;3*2
		.while esi<MAXYECHO-1
			mov		ax,word ptr STM32Echo[esi]
			mov		dx,word ptr STM32Echo[esi+MAXYECHO]
			mov		cx,word ptr STM32Echo[esi+MAXYECHO*2]
			.if (al<bl || ah<bl || dl<bl || dh<bl || cl<bl || ch<bl) 
				mov		al,0
			.else
				;Blend in 75% of previous echo
				movzx	edx,al
				movzx	eax,STM32Echo[esi+MAXYECHO]
				shl		eax,2
				add		eax,edx
				mov		ecx,5
				xor		edx,edx
				div		ecx
				.if al<bl
					mov		al,0
				.endif
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
		mov		sonardata.EchoArray[esi],al
	.else
		.while esi<MAXYECHO
			;Blend in 75% of previous echo
			movzx	eax,STM32Echo[esi+MAXYECHO]
			shl		eax,2
			movzx	edx,STM32Echo[esi]
			add		eax,edx
			mov		ecx,5
			xor		edx,edx
			div		ecx
			.if al<bl
				mov		al,0
			.endif
			mov		sonardata.EchoArray[esi],al
			inc		esi
		.endw
	.endif
	call	ScrollFish
	invoke SonarUpdateProc,1
	invoke DoSleep,edi
	retn

STMThread endp

SaveSonarToIni proc
	LOCAL	buffer[256]:BYTE

	mov		buffer,0
	;Width,AutoRange,AutoGain,AutoPing,FishDetect,FishAlarm,RangeInx,NoiseLevel,PingInit,GainSet,ChartSpeed,NoiseReject,PingTimer,SoundSpeed,SignalBarWt,FishDepth,ShowBottom,MinDepth
	invoke PutItemInt,addr buffer,sonardata.wt
	invoke PutItemInt,addr buffer,sonardata.AutoRange
	invoke PutItemInt,addr buffer,sonardata.AutoGain
	invoke PutItemInt,addr buffer,sonardata.AutoPing
	invoke PutItemInt,addr buffer,sonardata.FishDetect
	invoke PutItemInt,addr buffer,sonardata.FishAlarm
	movzx	eax,sonardata.RangeInx
	invoke PutItemInt,addr buffer,eax
	invoke PutItemInt,addr buffer,sonardata.NoiseLevel
	invoke PutItemInt,addr buffer,sonardata.PingInit
	invoke PutItemInt,addr buffer,sonardata.GainSet
	invoke PutItemInt,addr buffer,sonardata.ChartSpeed
	invoke PutItemInt,addr buffer,sonardata.NoiseReject
	movzx	eax,sonardata.PingTimer
	invoke PutItemInt,addr buffer,eax
	invoke PutItemInt,addr buffer,sonardata.SoundSpeed
	invoke PutItemInt,addr buffer,sonardata.SignalBarWt
	invoke PutItemInt,addr buffer,sonardata.FishDepth
	invoke PutItemInt,addr buffer,sonardata.fShowBottom
	invoke WritePrivateProfileString,addr szIniSonar,addr szIniSonar,addr buffer[1],addr szIniFileName
	ret

SaveSonarToIni endp

LoadSonarFromIni proc uses ebx esi edi
	LOCAL	buffer[256]:BYTE
	
	invoke RtlZeroMemory,addr buffer,sizeof buffer
	invoke GetPrivateProfileString,addr szIniSonar,addr szIniSonar,addr szNULL,addr buffer,sizeof buffer,addr szIniFileName
	;Width,AutoRange,AutoGain,AutoPing,FishDetect,FishAlarm,RangeInx,NoiseLevel,PingInit,GainSet,ChartSpeed,NoiseReject,PingTimer,SoundSpeed,SignalBarWt,FishDepth,ShowBottom,MinDepth
	invoke GetItemInt,addr buffer,250
	mov		sonardata.wt,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.AutoRange,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.AutoGain,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.AutoPing,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.FishDetect,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.FishAlarm,eax
	invoke GetItemInt,addr buffer,0
	mov		sonardata.RangeInx,al
	invoke GetItemInt,addr buffer,15
	mov		sonardata.NoiseLevel,eax
	invoke GetItemInt,addr buffer,63
	mov		sonardata.PingInit,eax
	invoke GetItemInt,addr buffer,630
	mov		sonardata.GainSet,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.ChartSpeed,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.NoiseReject,eax
	invoke GetItemInt,addr buffer,STM32_PingTimer
	mov		sonardata.PingTimer,al
	invoke GetItemInt,addr buffer,(SOUNDSPEEDMAX+SOUNDSPEEDMIN)/2
	mov		sonardata.SoundSpeed,eax
	invoke GetItemInt,addr buffer,32+8
	mov		sonardata.SignalBarWt,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.FishDepth,eax
	invoke GetItemInt,addr buffer,1
	mov		sonardata.fShowBottom,eax
	invoke GetPrivateProfileString,addr szIniSonarRange,addr szIniGainDef,addr szNULL,addr buffer,sizeof buffer,addr szIniFileName
	invoke GetItemInt,addr buffer,0
	mov		sonardata.gainofs,eax
	invoke GetItemInt,addr buffer,0
	mov		sonardata.gainmax,eax
	invoke GetItemInt,addr buffer,0
	mov		sonardata.gaindepth,eax
	;Get the range definitions
	xor		ebx,ebx
	xor		edi,edi
	.while ebx<32
		invoke wsprintf,addr buffer,addr szFmtDec,ebx
		invoke GetPrivateProfileString,addr szIniSonarRange,addr buffer,addr szNULL,addr buffer,sizeof buffer,addr szIniFileName
		.break .if !eax
		invoke GetItemInt,addr buffer,0
		mov		sonardata.sonarrange.range[edi],eax
		invoke GetItemInt,addr buffer,32
		mov		sonardata.sonarrange.mindepth[edi],eax
		invoke GetItemInt,addr buffer,0
		mov		sonardata.sonarrange.interval[edi],eax
		invoke GetItemInt,addr buffer,0
		mov		sonardata.sonarrange.pingadd[edi],eax
		xor		esi,esi
		.while esi<17
			invoke GetItemInt,addr buffer,0
			mov		sonardata.sonarrange.gain[edi+esi*DWORD],eax
			inc		esi
		.endw
		lea		esi,sonardata.sonarrange.scale[edi]
		invoke strcpy,esi,addr buffer
		xor		eax,eax
		.while byte ptr [esi]
			.if byte ptr [esi]==','
				inc		eax
				mov		byte ptr [esi],0
			.endif
			inc		esi
		.endw
		mov		sonardata.sonarrange.nticks[edi],eax
		inc		ebx
		lea		edi,[edi+sizeof RANGE]
	.endw
	;Store the number of range definitions read from ini
	mov		sonardata.MaxRange,ebx
	invoke SetupPixelTimer
	;Get the sonar colors
	invoke GetPrivateProfileString,addr szIniSonar,addr szIniSonarColor,addr szDefSonarColors,addr buffer,sizeof buffer,addr szIniFileName
	xor		ebx,ebx
	.while ebx<18
		invoke GetItemInt,addr buffer,0
		mov		sonardata.sonarcolor[ebx*DWORD],eax
		inc		ebx
	.endw
	invoke GetItemInt,addr buffer,0
	mov		sonardata.fGrayScale,eax
	ret

LoadSonarFromIni endp

SonarClear proc uses ebx esi
	LOCAL	rect:RECT

	invoke RtlZeroMemory,addr sonardata.fishdata,MAXFISH*sizeof FISH
	invoke RtlZeroMemory,addr STM32Echo,sizeof STM32Echo
	invoke RtlZeroMemory,addr sonardata.EchoArray,sizeof sonardata.EchoArray
	mov		rect.left,0
	mov		rect.top,0
	mov		rect.right,MAXXECHO
	mov		rect.bottom,MAXYECHO
	invoke FillRect,sonardata.mDC,addr rect,sonardata.hBrBack
	invoke GetClientRect,hSonar,addr rect
	mov		eax,sonardata.SignalBarWt
	mov		rect.right,eax
	
	invoke FillRect,sonardata.mDCS,addr rect,sonardata.hBrBack
	mov		esi,offset sonardata.sonarbmp
	mov		ebx,MAXSONARBMP
	.while ebx
		.if [esi].SONARBMP.hBmp
			invoke DeleteObject,[esi].SONARBMP.hBmp
			mov		[esi].SONARBMP.hBmp,0
		.endif
		lea		esi,[esi+sizeof SONARBMP]
		dec		ebx
	.endw
	movzx	eax,sonardata.RangeInx
	mov		sonardata.sonarbmp.RangeInx,eax
	mov		sonardata.sonarbmp.xpos,MAXXECHO
	mov		sonardata.sonarbmp.wt,0
	mov		sonardata.sonarbmp.hBmp,0
	inc		sonardata.PaintNow
	ret

SonarClear endp

ShowRangeDepthTempScaleFish proc uses ebx esi edi,hDC:HDC
	LOCAL	rcsonar:RECT
	LOCAL	rctext:RECT
	LOCAL	rect:RECT
	LOCAL	x:DWORD
	LOCAL	tmp:DWORD
	LOCAL	nticks:DWORD
	LOCAL	ntick:DWORD
	LOCAL	fishdepth:DWORD
	LOCAL	buffer[32]:BYTE

	invoke GetClientRect,hSonar,addr rcsonar
	call	ShowFish
	invoke SetBkMode,hDC,TRANSPARENT
	call	ShowScale
	xor		ebx,ebx
	mov		esi,offset sonardata.options
	.while ebx<MAXSONAROPTION
		.if [esi].OPTIONS.show
			.if ebx==1
				.if (sonardata.ShowDepth & 1) || (sonardata.ShowDepth>1)
					call ShowOption
				.endif
			.else
				call ShowOption
			.endif
		.endif
		lea		esi,[esi+sizeof OPTIONS]
		inc		ebx
	.endw
	.if sonardata.cursor
		mov		eax,sonardata.cursorpos
		mov		ecx,rcsonar.bottom
		sub		ecx,50
		mul		ecx
		mov		ecx,2048
		div		ecx
		add		eax,26
		mov		ebx,eax
		invoke CreatePen,PS_SOLID,4,0FFFFFFh
		invoke SelectObject,hDC,eax
		push	eax
		invoke MoveToEx,hDC,0,ebx,NULL
		invoke LineTo,hDC,rcsonar.right,ebx
		pop		eax
		invoke SelectObject,hDC,eax
		invoke DeleteObject,eax
		invoke CreatePen,PS_SOLID,2,0
		invoke SelectObject,hDC,eax
		push	eax
		invoke MoveToEx,hDC,0,ebx,NULL
		invoke LineTo,hDC,rcsonar.right,ebx
		pop		eax
		invoke SelectObject,hDC,eax
		invoke DeleteObject,eax
		push	ebx
		mov		ebx,sonardata.cursorpos
		shr		ebx,2
		add		ebx,13
		.if sonardata.zoom
			shr		ebx,1
			add		ebx,sonardata.zoomofs
			add		ebx,3
		.endif
		movzx	eax,STM32Echo
		invoke GetRangePtr,eax
		mov		eax,sonardata.sonarrange.range[eax]
		mov		ecx,10
		mul		ecx
		mul		ebx
		mov		ecx,MAXYECHO+23
		div		ecx
		invoke wsprintf,addr buffer,addr szFmtDec2,eax
		pop		ebx
		mov		rctext.left,10
		lea		eax,[ebx-22]
		mov		rctext.top,eax
		mov		rctext.right,100
		mov		rctext.bottom,ebx
		invoke strlen,addr buffer
		mov		cx,word ptr buffer[eax-1]
		mov		buffer[eax-1],'.'
		mov		word ptr buffer[eax],cx
		invoke TextDraw,hDC,mapdata.font[24],addr rctext,addr buffer,DT_LEFT or DT_SINGLELINE
	.endif
	ret

ShowFish:
	invoke CopyRect,addr rect,addr rcsonar
	.if sonardata.zoom
		shl		rect.bottom,1
		mov		eax,sonardata.zoomofs
		mov		ecx,rect.bottom
		mul		ecx
		mov		ecx,MAXYECHO
		div		ecx
		neg		eax
		mov		rect.top,eax
		add		rect.bottom,eax
	.endif
	invoke SetBkMode,hDC,TRANSPARENT
	movzx	eax,sonardata.EchoArray
	invoke GetRangePtr,eax
	mov		eax,sonardata.sonarrange.range[eax]
	mov		ebx,10
	mul		ebx
	mov		ebx,eax
	mov		ecx,MAXFISH
	mov		esi,offset sonardata.fishdata
	.while ecx
		push	ecx
		.if [esi].FISH.fishtype && sdword ptr [esi].FISH.xpos>=-10 && [esi].FISH.depth<=ebx
			mov		eax,[esi].FISH.depth
			mov		ecx,rect.bottom
			sub		ecx,rect.top
			cdq
			imul	ecx
			idiv	ebx
			add		eax,rect.top
			mov		edx,[esi].FISH.xpos
			mov		ecx,MAXXECHO
			add		ecx,sonardata.SignalBarWt
			sub		edx,ecx
			add		edx,rect.right
			push	eax
			push	edx
			invoke ImageList_Draw,hIml,[esi].FISH.fishtype,hDC,addr [edx-8],eax,ILD_TRANSPARENT
			pop		edx
			pop		eax
			.if sonardata.FishDepth
				sub		edx,16
				sub		eax,13
				mov		rctext.left,edx
				mov		rctext.top,eax
				add		edx,32
				mov		rctext.right,edx
				add		eax,16
				mov		rctext.bottom,eax
				mov		fishdepth,0
				invoke wsprintf,addr buffer,addr szFmtDec,[esi].FISH.depth
				invoke strlen,addr buffer
				.if buffer[eax-1]>='5'
					mov		fishdepth,1
				.endif
				mov		eax,[esi].FISH.depth
				xor		edx,edx
				mov		ecx,10
				div		ecx
				add		eax,fishdepth
				invoke wsprintf,addr buffer,addr szFmtDec,eax
				invoke TextDraw,hDC,mapdata.font[0],addr rctext,addr buffer,DT_CENTER or DT_SINGLELINE
			.endif
		.endif
		pop		ecx
		lea		esi,[esi+sizeof FISH]
		dec		ecx
	.endw
	retn

ShowOption:
	mov		ecx,[esi].OPTIONS.pt.x
	mov		edx,[esi].OPTIONS.pt.y
	mov		rect.left,ecx
	mov		rect.top,edx
	mov		eax,rcsonar.right
	sub		eax,ecx
	mov		rect.right,eax
	mov		eax,rcsonar.bottom
	sub		eax,edx
	mov		rect.bottom,eax
	mov		eax,[esi].OPTIONS.font
	add		eax,7
	mov		ecx,mapdata.font[eax*4]
	mov		edx,[esi].OPTIONS.position
	.if !edx
		;Left, Top
		mov		eax,DT_LEFT or DT_SINGLELINE
	.elseif edx==1
		;Center, Top
		mov		eax,DT_CENTER or DT_SINGLELINE
	.elseif edx==2
		;Rioght, Top
		mov		eax,DT_RIGHT or DT_SINGLELINE
	.elseif edx==3
		;Left, Bottom
		mov		eax,DT_LEFT or DT_BOTTOM or DT_SINGLELINE
	.elseif edx==4
		;Center, Bottom
		mov		eax,DT_CENTER or DT_BOTTOM or DT_SINGLELINE
	.elseif edx==5
		;Right, Bottom
		mov		eax,DT_RIGHT or DT_BOTTOM or DT_SINGLELINE
	.endif
	invoke TextDraw,hDC,ecx,addr rect,addr [esi].OPTIONS.text,eax
	retn

DrawTick:
	mov		eax,rect.bottom
	sub		eax,rect.top
	mov		tmp,eax
	fild	tmp
	fild	nticks
	fdivp	st(1),st
	fild	ntick
	fmulp	st(1),st
	fistp	tmp
	mov		eax,rect.top
	add		tmp,eax
	invoke MoveToEx,hDC,rect.left,tmp,NULL
	invoke LineTo,hDC,rect.right,tmp
	.if !ntick
		add		tmp,2
	.else
		sub		tmp,18
	.endif
	push	rect.left
	push	rect.top
	push	rect.right
	sub		rect.left,20
	add		rect.right,20
	mov		eax,tmp
	mov		rect.top,eax
	invoke TextDraw,hDC,NULL,addr rect,esi,DT_CENTER or DT_TOP or DT_SINGLELINE
	pop		rect.right
	pop		rect.top
	pop		rect.left
	retn

DrawScaleBar:
	mov		ebx,rect.right
	sub		ebx,rect.left
	shr		ebx,1
	add		ebx,rect.left
	invoke MoveToEx,hDC,ebx,rect.top,NULL
	invoke LineTo,hDC,ebx,rect.bottom
	movzx	eax,sonardata.EchoArray
	invoke GetRangePtr,eax
	mov		edx,sonardata.sonarrange.nticks[eax]
	mov		nticks,edx
	mov		ntick,0
	lea		esi,sonardata.sonarrange.scale[eax]
	.while dword ptr ntick<=edx
		push	edx
		call	DrawTick
		invoke strlen,esi
		lea		esi,[esi+eax+1]
		pop		edx
		inc		ntick
	.endw
	retn

ShowScale:
	invoke CopyRect,addr rect,addr rcsonar
	mov		eax,rect.right
	sub		eax,sonardata.SignalBarWt
	mov		rect.right,eax
	sub		eax,RANGESCALE
	mov		rect.left,eax
	add		rect.top,6
	sub		rect.bottom,5
	.if sonardata.zoom
		shl		rect.bottom,1
		mov		eax,sonardata.zoomofs
		mov		ecx,rect.bottom
		mul		ecx
		mov		ecx,MAXYECHO
		div		ecx
		neg		eax
		mov		rect.top,eax
		add		rect.bottom,eax
	.endif
	invoke CreatePen,PS_SOLID,5,0FFFFFFh
	invoke SelectObject,hDC,eax
	push	eax
	call	DrawScaleBar
	pop		eax
	invoke SelectObject,hDC,eax
	invoke DeleteObject,eax
	invoke GetStockObject,BLACK_PEN
	invoke SelectObject,hDC,eax
	push	eax
	call	DrawScaleBar
	pop		eax
	invoke SelectObject,hDC,eax
	retn

ShowRangeDepthTempScaleFish endp

SonarProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	ps:PAINTSTRUCT
	LOCAL	rect:RECT
	LOCAL	hDC:HDC
	LOCAL	mDC:HDC
	LOCAL	hBmp:HBITMAP
	LOCAL	pt:POINT

	mov		eax,uMsg
	.if eax==WM_CREATE
		mov		eax,hWin
		mov		hSonar,eax
		invoke CreateSolidBrush,sonardata.sonarcolor[17*DWORD]	;SONARBACKCOLOR
		mov		sonardata.hBrBack,eax
		invoke CreatePen,PS_SOLID,1,sonardata.sonarcolor[16*DWORD]	;SONARPENCOLOR
		mov		sonardata.hPen,eax
		invoke GetDC,hWin
		mov		hDC,eax

		invoke CreateCompatibleDC,hDC
		mov		sonardata.mDC,eax
		invoke CreateCompatibleBitmap,hDC,MAXXECHO,MAXYECHO
		mov		sonardata.hBmp,eax
		invoke SelectObject,sonardata.mDC,eax
		mov		sonardata.hBmpOld,eax
		mov		rect.left,0
		mov		rect.top,0
		mov		rect.right,MAXXECHO
		mov		rect.bottom,MAXYECHO
		invoke FillRect,sonardata.mDC,addr rect,sonardata.hBrBack

		invoke CreateCompatibleDC,hDC
		mov		sonardata.mDCS,eax
		invoke CreateCompatibleBitmap,hDC,sonardata.SignalBarWt,MAXYECHO
		mov		sonardata.hBmpS,eax
		invoke SelectObject,sonardata.mDCS,eax
		mov		sonardata.hBmpOldS,eax
		invoke SelectObject,sonardata.mDCS,sonardata.hPen
		mov		sonardata.hPenOld,eax
		mov		rect.left,0
		mov		rect.top,0
		mov		eax,sonardata.SignalBarWt
		mov		rect.right,eax
		mov		rect.bottom,MAXYECHO
		invoke FillRect,sonardata.mDCS,addr rect,sonardata.hBrBack

		invoke ReleaseDC,hWin,hDC
		invoke strcpy,addr sonardata.szFishSound,addr szAppPath
		invoke strcat,addr sonardata.szFishSound,addr szFishWav

		;Sonar init
		invoke EnableScrollBar,hSonar,SB_BOTH,ESB_DISABLE_BOTH
		invoke SetScrollRange,hSonar,SB_VERT,0,2048,TRUE
		invoke LoadCursor,hInstance,101
		mov		hSplittV,eax
		movzx	eax,sonardata.RangeInx
		invoke SetRange,eax

		movzx	eax,sonardata.RangeInx
		mov		sonardata.sonarbmp.RangeInx,eax
		mov		sonardata.sonarbmp.xpos,MAXXECHO
		mov		sonardata.sonarbmp.wt,0
		mov		sonardata.sonarbmp.hBmp,0

		invoke SetTimer,hWin,1000,800,NULL
		invoke SetTimer,hWin,1001,500,NULL
	.elseif eax==WM_PAINT
		invoke GetClientRect,hWin,addr rect
		invoke BeginPaint,hWin,addr ps
		invoke CreateCompatibleDC,ps.hdc
		mov		mDC,eax
		invoke CreateCompatibleBitmap,ps.hdc,rect.right,rect.bottom
		invoke SelectObject,mDC,eax
		push	eax
		invoke SetStretchBltMode,mDC,COLORONCOLOR
		invoke FillRect,mDC,addr rect,sonardata.hBrBack
		;Draw echo
		mov		eax,RANGESCALE
		add		eax,sonardata.SignalBarWt
		sub		rect.right,eax
		sub		rect.bottom,12
		mov		ecx,MAXXECHO
		sub		ecx,rect.right
		.if sonardata.zoom
			.if !sonardata.dptinx
				mov		eax,sonardata.zoomofs
			.else
				mov		eax,sonardata.dptinx
				shr		eax,1
				.if eax>256
					mov		eax,256
				.endif
				mov		edx,eax
				sub		edx,sonardata.zoomofs
				.if sdword ptr edx<0
					neg		edx
				.endif
				.if edx<ZOOMHYSTERESIS
					mov		eax,sonardata.zoomofs
				.endif
				mov		sonardata.zoomofs,eax
			.endif
			mov		edx,MAXYECHO/2
			invoke StretchBlt,mDC,0,6,rect.right,rect.bottom,sonardata.mDC,ecx,eax,rect.right,edx,SRCCOPY
		.else
			invoke StretchBlt,mDC,0,6,rect.right,rect.bottom,sonardata.mDC,ecx,0,rect.right,MAXYECHO,SRCCOPY
		.endif
		;Draw signal bar
		add		rect.right,RANGESCALE
		.if sonardata.zoom
			mov		eax,sonardata.zoomofs
			mov		edx,MAXYECHO/2
			invoke StretchBlt,mDC,rect.right,6,sonardata.SignalBarWt,rect.bottom,sonardata.mDCS,0,eax,sonardata.SignalBarWt,edx,SRCCOPY
		.else
			invoke StretchBlt,mDC,rect.right,6,sonardata.SignalBarWt,rect.bottom,sonardata.mDCS,0,0,sonardata.SignalBarWt,MAXYECHO,SRCCOPY
		.endif
		mov		eax,sonardata.SignalBarWt
		add		rect.right,eax
		invoke ShowRangeDepthTempScaleFish,mDC
		add		rect.bottom,12
		invoke BitBlt,ps.hdc,0,0,rect.right,rect.bottom,mDC,0,0,SRCCOPY
		pop		eax
		invoke SelectObject,mDC,eax
		invoke DeleteObject,eax
		invoke DeleteDC,mDC
		invoke EndPaint,hWin,addr ps
	.elseif eax==WM_TIMER
		.if wParam==1000
			.if !sonardata.fSTLink
				mov		sonardata.fSTLink,IDIGNORE
				mov		mapdata.fSTLink,IDIGNORE
				invoke STLinkConnect,hSonar
				.if eax==IDABORT
					invoke SendMessage,hWnd,WM_CLOSE,0,0
				.else
					mov		sonardata.fSTLink,eax
				.endif
				.if sonardata.fSTLink && sonardata.fSTLink!=IDIGNORE
					invoke STLinkReset,hSonar
					invoke STLinkConnect,hGPS
					.if eax==IDABORT
						invoke SendMessage,hWnd,WM_CLOSE,0,0
					.else
						mov		mapdata.fSTLink,eax
					.endif
					inc		sonardata.fGainUpload
				.endif
			.endif
		.elseif wParam==1001
			xor		sonardata.ShowDepth,1
			.if sonardata.ShowDepth<2
				invoke GetSonarOptionRect,1,addr rect
				invoke InvalidateRect,hSonar,addr rect,TRUE
			.endif
			.if sonardata.fFishSound
				dec		sonardata.fFishSound
			.endif
			xor		mapdata.fcursor,1
			.if mapdata.fcursor<2
				invoke GetMapOptionRect,0,addr rect
				invoke InvalidateRect,hMap,addr rect,TRUE
			.endif
		.endif
	.elseif eax==WM_CONTEXTMENU
		mov		eax,lParam
		.if eax!=-1
			movsx	edx,ax
			mov		mousept.x,edx
			mov		pt.x,edx
			shr		eax,16
			movsx	edx,ax
			mov		mousept.y,edx
			mov		pt.y,edx
			invoke GetSubMenu,hContext,5
			invoke TrackPopupMenu,eax,TPM_LEFTALIGN or TPM_RIGHTBUTTON,mousept.x,mousept.y,0,hWnd,0
		.endif
	.elseif eax==WM_DESTROY
		invoke SonarClear
		invoke DeleteObject,sonardata.hBrBack
		invoke SelectObject,sonardata.mDC,sonardata.hBmpOld
		invoke DeleteObject,sonardata.hBmp
		invoke DeleteDC,sonardata.mDC
		invoke SelectObject,sonardata.mDCS,sonardata.hBmpOldS
		invoke DeleteObject,sonardata.hBmpS
		invoke SelectObject,sonardata.mDCS,sonardata.hPenOld
		invoke DeleteObject,sonardata.hPen
		invoke DeleteDC,sonardata.mDCS
		invoke SaveSonarToIni
	.elseif eax==WM_HSCROLL
		mov		eax,wParam
		movzx	edx,ax
		shr		eax,16
		.if edx==SB_THUMBPOSITION
			.if sonardata.hReplay
				push	eax
				invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
				pop		eax
				mov		ecx,MAXYECHO
				.if sonarreplay.Version==200
					add		ecx,sizeof SONARREPLAY
				.elseif sonarreplay.Version==201
					add		ecx,sizeof SONARREPLAY+sizeof SATELITE*12+sizeof ALTITUDE
				.endif
				mul		ecx
				invoke SetFilePointer,sonardata.hReplay,eax,NULL,FILE_BEGIN
			.endif
		.elseif edx==SB_LINERIGHT
			.if sonardata.hReplay
				invoke GetScrollPos,hWin,SB_HORZ
				add		eax,16
				push	eax
				invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
				pop		eax
				mov		ecx,MAXYECHO
				.if sonarreplay.Version==200
					add		ecx,sizeof SONARREPLAY
				.elseif sonarreplay.Version==201
					add		ecx,sizeof SONARREPLAY+sizeof SATELITE*12+sizeof ALTITUDE
				.endif
				mul		ecx
				invoke SetFilePointer,sonardata.hReplay,eax,NULL,FILE_BEGIN
			.endif
		.elseif edx==SB_LINELEFT
			.if sonardata.hReplay
				.while sonardata.fReplayRead
				.endw
				invoke GetScrollPos,hWin,SB_HORZ
				sub		eax,16
				.if CARRY?
					xor		eax,eax
				.endif
				push	eax
				invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
				pop		eax
				mov		ecx,MAXYECHO
				.if sonarreplay.Version==200
					add		ecx,sizeof SONARREPLAY
				.elseif sonarreplay.Version==201
					add		ecx,sizeof SONARREPLAY+sizeof SATELITE*12+sizeof ALTITUDE
				.endif
				mul		ecx
				invoke SetFilePointer,sonardata.hReplay,eax,NULL,FILE_BEGIN
			.endif
		.elseif edx==SB_PAGERIGHT
			.if sonardata.hReplay
				.while sonardata.fReplayRead
				.endw
				invoke GetScrollPos,hWin,SB_HORZ
				add		eax,256
				push	eax
				invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
				pop		eax
				mov		ecx,MAXYECHO
				.if sonarreplay.Version==200
					add		ecx,sizeof SONARREPLAY
				.elseif sonarreplay.Version==201
					add		ecx,sizeof SONARREPLAY+sizeof SATELITE*12+sizeof ALTITUDE
				.endif
				mul		ecx
				invoke SetFilePointer,sonardata.hReplay,eax,NULL,FILE_BEGIN
			.endif
		.elseif edx==SB_PAGELEFT
			.if sonardata.hReplay
				.while sonardata.fReplayRead
				.endw
				invoke GetScrollPos,hWin,SB_HORZ
				sub		eax,256
				.if CARRY?
					xor		eax,eax
				.endif
				push	eax
				invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
				pop		eax
				mov		ecx,MAXYECHO
				.if sonarreplay.Version==200
					add		ecx,sizeof SONARREPLAY
				.elseif sonarreplay.Version==201
					add		ecx,sizeof SONARREPLAY+sizeof SATELITE*12+sizeof ALTITUDE
				.endif
				mul		ecx
				invoke SetFilePointer,sonardata.hReplay,eax,NULL,FILE_BEGIN
			.endif
		.endif
	.elseif eax==WM_VSCROLL
		mov		eax,wParam
		movzx	edx,ax
		shr		eax,16
		.if edx==SB_THUMBTRACK
			.while sonardata.fReplayRead
			.endw
			mov		sonardata.cursorpos,eax
			invoke SetScrollPos,hWin,SB_VERT,eax,TRUE
			inc		sonardata.PaintNow
		.elseif edx==SB_LINERIGHT
			.while sonardata.fReplayRead
			.endw
			invoke GetScrollPos,hWin,SB_VERT
			.if eax<2048
				inc		eax
				mov		sonardata.cursorpos,eax
				invoke SetScrollPos,hWin,SB_VERT,eax,TRUE
				inc		sonardata.PaintNow
			.endif
		.elseif edx==SB_LINELEFT
			.while sonardata.fReplayRead
			.endw
			invoke GetScrollPos,hWin,SB_VERT
			.if eax
				dec		eax
				mov		sonardata.cursorpos,eax
				invoke SetScrollPos,hWin,SB_VERT,eax,TRUE
				inc		sonardata.PaintNow
			.endif
		.elseif edx==SB_PAGERIGHT
			.while sonardata.fReplayRead
			.endw
			invoke GetScrollPos,hWin,SB_VERT
			add		eax,32
			.if eax>2048
				mov		eax,2048
			.endif
			mov		sonardata.cursorpos,eax
			invoke SetScrollPos,hWin,SB_VERT,eax,TRUE
			inc		sonardata.PaintNow
		.elseif edx==SB_PAGELEFT
			.while sonardata.fReplayRead
			.endw
			invoke GetScrollPos,hWin,SB_VERT
			sub		eax,32
			.if CARRY?
				xor		eax,eax
			.endif
			mov		sonardata.cursorpos,eax
			invoke SetScrollPos,hWin,SB_VERT,eax,TRUE
			inc		sonardata.PaintNow
		.endif
	.else
		invoke DefWindowProc,hWin,uMsg,wParam,lParam
		ret
	.endif
	xor    eax,eax
	ret

SonarProc endp
