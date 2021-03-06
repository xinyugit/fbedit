
.code

ButtonProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	.data?
		nCount		DWORD ?
	.code
	mov		eax,uMsg
	.if eax==WM_LBUTTONDOWN || eax==WM_LBUTTONDBLCLK
		mov		nCount,16
		invoke SetTimer,hWin,1000,500,NULL
	.elseif eax==WM_LBUTTONUP
		invoke KillTimer,hWin,1000
		mov		nCount,16
	.elseif eax==WM_TIMER
		invoke GetWindowLong,hWin,GWL_ID
		mov		ebx,eax
		invoke GetParent,hWin
		mov		esi,eax
		.if esi==hWnd
			invoke SendMessage,esi,WM_COMMAND,ebx,hWin
		.else
			invoke SendMessage,esi,WM_COMMAND,ebx,hWin
			mov		edi,nCount
			shr		edi,4
			.if edi>40
				mov		edi,40
			.endif
			.while edi
				invoke SendMessage,esi,WM_COMMAND,ebx,hWin
				dec		edi
			.endw
			invoke KillTimer,hWin,1000
			invoke SetTimer,hWin,1000,50,NULL
		.endif
		inc		nCount
		xor		eax,eax
		ret
	.endif
	invoke CallWindowProc,lpOldButtonProc,hWin,uMsg,wParam,lParam
	ret

ButtonProc endp

MakeHSCWave proc  uses ebx esi edi, lpWave:DWORD,Duty:DWORD

	mov		edi,lpWave
	.if !Duty
		mov		byte ptr [edi],0
	.elseif Duty==100
		mov		byte ptr [edi],ADCMAX
	.else
		mov		byte ptr [edi],ADCMAX/2
	.endif
	inc		edi
	xor		ebx,ebx
	.while ebx<2
		xor		ecx,ecx
		mov		edx,ADCMAX
		.while ecx<HSCMAX/2-1
			.if ecx==Duty
				xor		edx,edx
			.endif
			mov		[edi+ecx],dl
			inc		ecx
		.endw
		lea		edi,[edi+ecx]
		inc		ebx
	.endw
	.if !Duty
		mov		byte ptr [edi],0
	.elseif Duty==100
		mov		byte ptr [edi],ADCMAX
	.else
		mov		byte ptr [edi],ADCMAX/2
	.endif
	ret

MakeHSCWave endp

FrequencyToClock proc uses ebx,frq:DWORD,clk:DWORD

	mov		ebx,1
	.while TRUE
		mov		eax,clk
		cdq
		div		ebx
		cdq
		mov		ecx,frq
		div		ecx
		.if eax<=65535
			mov		edx,ebx
			.break
		.endif
		inc		ebx
	.endw
	ret

FrequencyToClock endp

ClockToFrequency proc count:DWORD,clkdiv:DWORD,clk:DWORD

	mov		eax,clk
	cdq
	mov		ecx,clkdiv
	div		ecx
	cdq
	mov		ecx,count
	div		ecx
	ret

ClockToFrequency endp

HSClockSetupProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	tmp:DWORD
	LOCAL	fChanged:DWORD

	mov		eax,uMsg
	.if eax==WM_INITDIALOG
		;Channel A
		mov		eax,BST_UNCHECKED
		.if hsclockdata.hscCHAData.hsclockenable
			mov		eax,BST_CHECKED
		.endif
		invoke CheckDlgButton,hWin,IDC_CHKHSCLOCKAENABLE,eax
		movzx	eax,hsclockdata.hscCHAData.hsclockdutycycle
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKADUTY,TBM_SETPOS,TRUE,eax
		movzx	eax,hsclockdata.hscCHAData.hsclockfrequency
		movzx	edx,hsclockdata.hscCHAData.hsclockdivisor
		invoke ClockToFrequency,eax,edx,STM32ClockDiv2
		invoke SetDlgItemInt,hWin,IDC_EDTFRQCHA,eax,FALSE
		invoke SendDlgItemMessage,hWin,IDC_EDTFRQCHA,EM_LIMITTEXT,8,0

		;Channel B
		mov		eax,BST_UNCHECKED
		.if hsclockdata.hscCHBData.hsclockenable
			mov		eax,BST_CHECKED
		.endif
		invoke CheckDlgButton,hWin,IDC_CHKHSCLOCKBENABLE,eax
		movzx	eax,hsclockdata.hscCHBData.hsclockdutycycle
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKBDUTY,TBM_SETPOS,TRUE,eax
		movzx	eax,hsclockdata.hscCHBData.hsclockfrequency
		movzx	edx,hsclockdata.hscCHBData.hsclockdivisor
		invoke ClockToFrequency,eax,edx,STM32Clock
		invoke SetDlgItemInt,hWin,IDC_EDTFRQCHB,eax,FALSE
		invoke SendDlgItemMessage,hWin,IDC_EDTFRQCHB,EM_LIMITTEXT,8,0
		push	0
		push	IDC_BTNFRQCHADN
		push	IDC_BTNFRQCHAUP
		push	IDC_BTNFRQCHBDN
		mov		eax,IDC_BTNFRQCHBUP
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
			.if eax==IDCANCEL
				invoke SendMessage,hWin,WM_CLOSE,0,1
			.elseif eax==IDC_CHKHSCLOCKAENABLE
				invoke IsDlgButtonChecked,hWin,IDC_CHKHSCLOCKAENABLE
				mov		hsclockdata.hscCHAData.hsclockenable,eax
				mov		fHSCCHA,TRUE
			.elseif eax==IDC_BTNFRQCHADN
				invoke GetDlgItemInt,hWin,IDC_EDTFRQCHA,NULL,FALSE
				.if eax>1
					mov		ebx,eax
					mov		edi,eax
					.while TRUE
						dec		ebx
						invoke FrequencyToClock,ebx,STM32ClockDiv2
						mov		hsclockdata.hscCHAData.hsclockfrequency,ax
						mov		hsclockdata.hscCHAData.hsclockdivisor,dx
						invoke ClockToFrequency,eax,edx,STM32ClockDiv2
						.break .if eax!=edi
					.endw
					invoke SetDlgItemInt,hWin,IDC_EDTFRQCHA,eax,FALSE
					invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKADUTY,TBM_GETPOS,0,0
					movzx	ecx,hsclockdata.hscCHAData.hsclockfrequency
					mul		ecx
					mov		ecx,100
					div		ecx
					mov		hsclockdata.hscCHAData.hsclockccr,ax
					invoke InvalidateRect,hsclockdata.hscCHAData.hWndHSClock,NULL,TRUE
					mov		fHSCCHA,TRUE
				.endif
			.elseif eax==IDC_BTNFRQCHAUP
				invoke GetDlgItemInt,hWin,IDC_EDTFRQCHA,NULL,FALSE
				.if eax<21000000
					mov		ebx,eax
					mov		edi,eax
					.while TRUE
						inc		ebx
						invoke FrequencyToClock,ebx,STM32ClockDiv2
						mov		hsclockdata.hscCHAData.hsclockfrequency,ax
						mov		hsclockdata.hscCHAData.hsclockdivisor,dx
						invoke ClockToFrequency,eax,edx,STM32ClockDiv2
						.break .if eax!=edi
					.endw
					invoke SetDlgItemInt,hWin,IDC_EDTFRQCHA,eax,FALSE
					invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKADUTY,TBM_GETPOS,0,0
					movzx	ecx,hsclockdata.hscCHAData.hsclockfrequency
					mul		ecx
					mov		ecx,100
					div		ecx
					mov		hsclockdata.hscCHAData.hsclockccr,ax
					invoke InvalidateRect,hsclockdata.hscCHAData.hWndHSClock,NULL,TRUE
					mov		fHSCCHA,TRUE
				.endif
			.elseif eax==IDC_CHKHSCLOCKBENABLE
				invoke IsDlgButtonChecked,hWin,IDC_CHKHSCLOCKBENABLE
				mov		hsclockdata.hscCHBData.hsclockenable,eax
				mov		fHSCCHB,TRUE
			.elseif eax==IDC_BTNFRQCHBDN
				invoke GetDlgItemInt,hWin,IDC_EDTFRQCHB,NULL,FALSE
				.if eax>1
					mov		ebx,eax
					mov		edi,eax
					.while TRUE
						dec		ebx
						invoke FrequencyToClock,ebx,STM32Clock
						mov		hsclockdata.hscCHBData.hsclockfrequency,ax
						mov		hsclockdata.hscCHBData.hsclockdivisor,dx
						invoke ClockToFrequency,eax,edx,STM32Clock
						.break .if eax!=edi
					.endw
					invoke SetDlgItemInt,hWin,IDC_EDTFRQCHB,eax,FALSE
					invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKBDUTY,TBM_GETPOS,0,0
					movzx	ecx,hsclockdata.hscCHBData.hsclockfrequency
					mul		ecx
					mov		ecx,100
					div		ecx
					mov		hsclockdata.hscCHBData.hsclockccr,ax
					invoke InvalidateRect,hsclockdata.hscCHBData.hWndHSClock,NULL,TRUE
					mov		fHSCCHB,TRUE
				.endif
			.elseif eax==IDC_BTNFRQCHBUP
				invoke GetDlgItemInt,hWin,IDC_EDTFRQCHB,NULL,FALSE
				.if eax<42000000
					mov		ebx,eax
					mov		edi,eax
					.while TRUE
						inc		ebx
						invoke FrequencyToClock,ebx,STM32Clock
						mov		hsclockdata.hscCHBData.hsclockfrequency,ax
						mov		hsclockdata.hscCHBData.hsclockdivisor,dx
						invoke ClockToFrequency,eax,edx,STM32Clock
						.break .if eax!=edi
					.endw
					invoke SetDlgItemInt,hWin,IDC_EDTFRQCHB,eax,FALSE
					invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKBDUTY,TBM_GETPOS,0,0
					movzx	ecx,hsclockdata.hscCHBData.hsclockfrequency
					mul		ecx
					mov		ecx,100
					div		ecx
					mov		hsclockdata.hscCHBData.hsclockccr,ax
					invoke InvalidateRect,hsclockdata.hscCHBData.hWndHSClock,NULL,TRUE
					mov		fHSCCHB,TRUE
				.endif
			.endif
		.elseif edx==EN_KILLFOCUS
			.if eax==IDC_EDTFRQCHA
				invoke GetDlgItemInt,hWin,IDC_EDTFRQCHA,0,FALSE
				.if !eax
					inc		eax
				.elseif eax>21000000
					mov		eax,21000000
				.endif
				invoke FrequencyToClock,eax,STM32ClockDiv2
				mov		hsclockdata.hscCHAData.hsclockfrequency,ax
				mov		hsclockdata.hscCHAData.hsclockdivisor,dx
				invoke ClockToFrequency,eax,edx,STM32ClockDiv2
				invoke SetDlgItemInt,hWin,IDC_EDTFRQCHA,eax,FALSE
				invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKADUTY,TBM_GETPOS,0,0
				movzx	ecx,hsclockdata.hscCHAData.hsclockfrequency
				mul		ecx
				mov		ecx,100
				div		ecx
				mov		hsclockdata.hscCHAData.hsclockccr,ax
				invoke InvalidateRect,hsclockdata.hscCHAData.hWndHSClock,NULL,TRUE
				mov		fHSCCHA,TRUE
			.elseif eax==IDC_EDTFRQCHB
				invoke GetDlgItemInt,hWin,IDC_EDTFRQCHB,0,FALSE
				.if !eax
					inc		eax
				.elseif eax>42000000
					mov		eax,42000000
				.endif
				invoke FrequencyToClock,eax,STM32Clock
				mov		hsclockdata.hscCHBData.hsclockfrequency,ax
				mov		hsclockdata.hscCHBData.hsclockdivisor,dx
				invoke ClockToFrequency,eax,edx,STM32Clock
				invoke SetDlgItemInt,hWin,IDC_EDTFRQCHB,eax,FALSE
				invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKBDUTY,TBM_GETPOS,0,0
				movzx	ecx,hsclockdata.hscCHBData.hsclockfrequency
				mul		ecx
				mov		ecx,100
				div		ecx
				mov		hsclockdata.hscCHBData.hsclockccr,ax
				invoke InvalidateRect,hsclockdata.hscCHBData.hWndHSClock,NULL,TRUE
				mov		fHSCCHB,TRUE
			.endif
		.endif
	.elseif eax==WM_HSCROLL
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKADUTY,TBM_GETPOS,0,0
		.if ax!=hsclockdata.hscCHAData.hsclockdutycycle
			mov		hsclockdata.hscCHAData.hsclockdutycycle,ax
			movzx	ecx,hsclockdata.hscCHAData.hsclockfrequency
			mul		ecx
			mov		ecx,100
			div		ecx
			mov		hsclockdata.hscCHAData.hsclockccr,ax
			movzx	eax,hsclockdata.hscCHAData.hsclockccr
			mov		ecx,100
			mul		ecx
			movzx	ecx,hsclockdata.hscCHAData.hsclockfrequency
			div		ecx
			invoke MakeHSCWave,addr hsclockdata.hscCHAData.HSC_Data,eax
			invoke InvalidateRect,hsclockdata.hscCHAData.hWndHSClock,NULL,TRUE
			mov		fHSCCHA,TRUE
		.endif
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKBDUTY,TBM_GETPOS,0,0
		.if ax!=hsclockdata.hscCHBData.hsclockdutycycle
			mov		hsclockdata.hscCHBData.hsclockdutycycle,ax
			movzx	ecx,hsclockdata.hscCHBData.hsclockfrequency
			mul		ecx
			mov		ecx,100
			div		ecx
			mov		hsclockdata.hscCHBData.hsclockccr,ax
			movzx	eax,hsclockdata.hscCHBData.hsclockccr
			mov		ecx,100
			mul		ecx
			movzx	ecx,hsclockdata.hscCHBData.hsclockfrequency
			div		ecx
			invoke MakeHSCWave,addr hsclockdata.hscCHBData.HSC_Data,eax
			invoke InvalidateRect,hsclockdata.hscCHBData.hWndHSClock,NULL,TRUE
			mov		fHSCCHB,TRUE
		.endif
	.elseif eax==WM_ACTIVATE
		mov		eax,wParam
		.if eax!=WA_INACTIVE
			mov		eax,hWin
			mov		hDlg,eax
		.endif
	.elseif eax==WM_CLOSE
		invoke DestroyWindow,hWin
		mov		childdialogs.hWndHSClockSetup,0
		invoke SetFocus,hWnd
	.else
		mov		eax,FALSE
		ret
	.endif
	mov		eax,TRUE
	ret

HSClockSetupProc endp

HSClockToolChildProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM

	mov		eax,uMsg
	.if eax==WM_INITDIALOG
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKXMAG,TBM_SETRANGE,FALSE,(XMAGMAX SHL 16)+1
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKXMAG,TBM_SETPOS,TRUE,XMAGMAX/16
	.elseif eax==WM_HSCROLL
		;X-Magnification
		invoke GetParent,hWin
		invoke GetWindowLong,eax,GWL_USERDATA
		mov		ebx,eax
		invoke SendDlgItemMessage,hWin,IDC_TRBHSCLOCKXMAG,TBM_GETPOS,0,0
		mov		[ebx].HSCLOCKCHDATA.xmag,eax
		invoke InvalidateRect,[ebx].HSCLOCKCHDATA.hWndHSClock,NULL,TRUE
	.else
		mov		eax,FALSE
		ret
	.endif
	mov		eax,TRUE
	ret

HSClockToolChildProc endp

HSClockProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	ps:PAINTSTRUCT
	LOCAL	rect:RECT
	LOCAL	mDC:HDC
	LOCAL	pt:POINT
	LOCAL	xsinf:SCROLLINFO
	LOCAL	samplesize:DWORD
	LOCAL	buffer[128]:BYTE
	LOCAL	buffer1[128]:BYTE

	mov		eax,uMsg
	.if eax==WM_CREATE
		xor		eax,eax
		mov		xsinf.cbSize,sizeof SCROLLINFO
		mov		xsinf.fMask,SIF_ALL
		invoke GetScrollInfo,hWin,SB_HORZ,addr xsinf
		mov		eax,xsinf.nMax
		inc		eax
		mov		xsinf.nPage,eax
		invoke SetScrollInfo,hWin,SB_HORZ,addr xsinf,TRUE
	.elseif eax==WM_PAINT
		invoke GetParent,hWin
		invoke GetWindowLong,eax,GWL_USERDATA
		mov		ebx,eax
		invoke GetClientRect,hWin,addr rect
		call	SetScrooll
		invoke BeginPaint,hWin,addr ps
		invoke CreateCompatibleDC,ps.hdc
		mov		mDC,eax
		invoke CreateCompatibleBitmap,ps.hdc,rect.right,rect.bottom
		invoke SelectObject,mDC,eax
		push	eax
		invoke GetStockObject,BLACK_BRUSH
		invoke FillRect,mDC,addr rect,eax
		;Draw horizontal lines
		sub		rect.bottom,TEXTHIGHT
		invoke CreatePen,PS_SOLID,1,0303030h
		invoke SelectObject,mDC,eax
		push	eax
		mov		eax,rect.bottom
		mov		ecx,6
		xor		edx,edx
		div		ecx
		mov		edx,eax
		mov		edi,eax
		xor		ecx,ecx
		.while ecx<5
			push	ecx
			push	edx
			invoke MoveToEx,mDC,0,edi,NULL
			invoke LineTo,mDC,rect.right,edi
			pop		edx
			add		edi,edx
			pop		ecx
			inc		ecx
		.endw
		invoke MoveToEx,mDC,0,rect.bottom,NULL
		invoke LineTo,mDC,rect.right,rect.bottom
		;Draw vertical lines
		mov		eax,rect.right
		mov		ecx,10
		xor		edx,edx
		div		ecx
		mov		edx,eax
		mov		edi,eax
		xor		ecx,ecx
		.while ecx<9
			push	ecx
			push	edx
			invoke MoveToEx,mDC,edi,0,NULL
			invoke LineTo,mDC,edi,rect.bottom
			pop		edx
			add		edi,edx
			pop		ecx
			inc		ecx
		.endw
		pop		eax
		invoke SelectObject,mDC,eax
		invoke DeleteObject,eax
		;Draw curve
		mov		eax,hWin
		.if eax==hsclockdata.hscCHAData.hWndHSClock
			;Channel A
			invoke SetTextColor,mDC,00FF00h
			mov		eax,008000h
		.else
			;Channel B
			invoke SetTextColor,mDC,0FFFF00h
			mov		eax,0808000h
		.endif
		invoke CreatePen,PS_SOLID,2,eax
		invoke SelectObject,mDC,eax
		push	eax
		invoke SetBkMode,mDC,TRANSPARENT
		lea		esi,[ebx].HSCLOCKCHDATA.HSC_Data
		xor		edi,edi
		call	GetPoint
		invoke MoveToEx,mDC,pt.x,pt.y,NULL
		.while edi<samplesize
			mov		edx,edi
			call	GetPoint
			.if sdword ptr pt.x>=0
				invoke LineTo,mDC,pt.x,pt.y
				mov		eax,pt.x
				.break .if sdword ptr eax>rect.right
			.else
				invoke MoveToEx,mDC,pt.x,pt.y,NULL
			.endif
			inc		edi
		.endw
		pop		eax
		invoke SelectObject,mDC,eax
		invoke DeleteObject,eax
		movzx	ecx,[ebx].HSCLOCKCHDATA.hsclockdivisor
		mov		eax,hWin
		.if eax==hsclockdata.hscCHAData.hWndHSClock
			;Channel A
			mov		eax,STM32ClockDiv2
		.else
			;Channel B
			mov		eax,STM32Clock
		.endif
		cdq
		div		ecx
		cdq
		movzx	ecx,[ebx].HSCLOCKCHDATA.hsclockfrequency
		div		ecx
		push	eax
		movzx	eax,[ebx].HSCLOCKCHDATA.hsclockccr
		mov		ecx,100
		mul		ecx
		movzx	ecx,[ebx].HSCLOCKCHDATA.hsclockfrequency
		div		ecx
		pop		edx
		push	eax
		invoke FormatFrequency,addr buffer,addr szFmtFrq,edx
		pop		eax
		invoke wsprintf,addr buffer1,addr szFmtDuty,eax
		invoke lstrcat,addr buffer,addr buffer1
		invoke lstrlen,addr buffer
		mov		edx,rect.bottom
		add		edx,8
		invoke TextOut,mDC,0,edx,addr buffer,eax
		add		rect.bottom,TEXTHIGHT
		invoke BitBlt,ps.hdc,0,0,rect.right,rect.bottom,mDC,0,0,SRCCOPY
		pop		eax
		invoke SelectObject,mDC,eax
		invoke DeleteObject,eax
		invoke DeleteDC,mDC
		invoke EndPaint,hWin,addr ps
		xor		eax,eax
	.elseif eax==WM_HSCROLL
		mov		xsinf.cbSize,sizeof SCROLLINFO
		mov		xsinf.fMask,SIF_ALL
		invoke GetScrollInfo,hWin,SB_HORZ,addr xsinf
		mov		eax,wParam
		movzx	eax,ax
		.if eax==SB_THUMBPOSITION
			mov		eax,xsinf.nTrackPos
			invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
			invoke InvalidateRect,hWin,NULL,TRUE
		.elseif  eax==SB_THUMBTRACK
			mov		eax,xsinf.nTrackPos
			invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
			invoke InvalidateRect,hWin,NULL,TRUE
		.elseif  eax==SB_LINELEFT
			mov		eax,xsinf.nPos
			sub		eax,10
			.if CARRY?
				xor		eax,eax
			.endif
			invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
			invoke InvalidateRect,hWin,NULL,TRUE
		.elseif eax==SB_LINERIGHT
			mov		eax,xsinf.nPos
			add		eax,10
			invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
			invoke InvalidateRect,hWin,NULL,TRUE
		.elseif eax==SB_PAGELEFT
			mov		eax,xsinf.nPos
			sub		eax,xsinf.nPage
			.if CARRY?
				xor		eax,eax
			.endif
			invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
			invoke InvalidateRect,hWin,NULL,TRUE
		.elseif eax==SB_PAGERIGHT
			mov		eax,xsinf.nPos
			add		eax,xsinf.nPage
			invoke SetScrollPos,hWin,SB_HORZ,eax,TRUE
			invoke InvalidateRect,hWin,NULL,TRUE
		.endif
		xor		eax,eax
	.else
		invoke DefWindowProc,hWin,uMsg,wParam,lParam
	.endif
	ret

SetScrooll:
	invoke GetParent,hWin
	invoke GetWindowLong,eax,GWL_USERDATA
	mov		ebx,eax
	mov		samplesize,HSCMAX
	invoke GetClientRect,hWin,addr rect
	;Init horizontal scrollbar
	mov		xsinf.cbSize,sizeof SCROLLINFO
	mov		xsinf.fMask,SIF_ALL
	invoke GetScrollInfo,hWin,SB_HORZ,addr xsinf
	mov		xsinf.nMin,0
	mov		eax,samplesize
	mov		ecx,[ebx].HSCLOCKCHDATA.xmag
	.if ecx>XMAGMAX/16
		sub		ecx,XMAGMAX/16
		add		ecx,10
		mul		ecx
		mov		ecx,10
		div		ecx
	.elseif ecx<XMAGMAX/16
		push	ecx
		mov		ecx,10
		mul		ecx
		pop		ecx
		sub		ecx,XMAGMAX/16
		neg		ecx
		add		ecx,10
		div		ecx
	.endif
	mov		ecx,rect.right
	mul		ecx
	mov		ecx,samplesize
	div		ecx
	mov		xsinf.nMax,eax
	mov		eax,rect.right
	inc		eax
	mov		xsinf.nPage,eax
	invoke SetScrollInfo,hWin,SB_HORZ,addr xsinf,TRUE
	retn

GetPoint:
	;Get X position
	mov		eax,edi
	mov		ecx,[ebx].HSCLOCKCHDATA.xmag
	.if ecx>XMAGMAX/16
		sub		ecx,XMAGMAX/16
		add		ecx,10
		mul		ecx
		mov		ecx,10
		div		ecx
	.elseif ecx<XMAGMAX/16
		push	ecx
		mov		ecx,10
		mul		ecx
		pop		ecx
		sub		ecx,XMAGMAX/16
		neg		ecx
		add		ecx,10
		div		ecx
	.endif
	mov		ecx,rect.right
	mul		ecx
	mov		ecx,samplesize
	div		ecx
	sub		eax,xsinf.nPos
	mov		pt.x,eax
	;Get y position
	mov		edx,edi
	movzx	eax,byte ptr [esi+edx]
	sub		eax,ADCMAX
	neg		eax
	mov		ecx,rect.bottom
	sub		ecx,10
	mul		ecx
	mov		ecx,ADCMAX
	div		ecx
	add		eax,5
	mov		pt.y,eax
	retn

HSClockProc endp

HSClockChildProc proc uses ebx esi edi,hWin:HWND,uMsg:UINT,wParam:WPARAM,lParam:LPARAM
	LOCAL	rect:RECT

	mov		eax,uMsg
	.if eax==WM_INITDIALOG
		mov		ebx,lParam
		invoke SetWindowLong,hWin,GWL_USERDATA,ebx
		mov		eax,hWin
		mov		[ebx].HSCLOCKCHDATA.hWndDialog,eax
		invoke GetDlgItem,hWin,IDC_UDCHSCLOCK
		mov		[ebx].HSCLOCKCHDATA.hWndHSClock,eax
		invoke CreateDialogParam,hInstance,IDD_DLGHSCLOCKTOOL,hWin,addr HSClockToolChildProc,0
		mov		[ebx].HSCLOCKCHDATA.hWndHSClockTool,eax
		mov		[ebx].HSCLOCKCHDATA.hsclockfrequency,55999
		mov		[ebx].HSCLOCKCHDATA.hsclockdivisor,2
		mov		[ebx].HSCLOCKCHDATA.hsclockccr,27999
		mov		[ebx].HSCLOCKCHDATA.hsclockdutycycle,50
		mov		[ebx].HSCLOCKCHDATA.xmag,XMAGMAX/16
		invoke MakeHSCWave,addr [ebx].HSCLOCKCHDATA.HSC_Data,[ebx].HSCLOCKCHDATA.hsclockdutycycle
	.elseif	eax==WM_SIZE
		invoke GetWindowLong,hWin,GWL_USERDATA
		mov		ebx,eax
		invoke GetClientRect,hWin,addr rect
		sub		rect.right,135
		sub		rect.bottom,2
		invoke MoveWindow,[ebx].HSCLOCKCHDATA.hWndHSClock,0,0,rect.right,rect.bottom,TRUE
		invoke MoveWindow,[ebx].HSCLOCKCHDATA.hWndHSClockTool,rect.right,0,135,60,TRUE
	.elseif eax==WM_CLOSE
		invoke DestroyWindow,hWin
	.else
		mov		eax,FALSE
		ret
	.endif
	mov		eax,TRUE
	ret

HSClockChildProc endp

