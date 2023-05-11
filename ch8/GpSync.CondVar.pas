{:Conditional variable wrapper.
  @author Primoz Gabrijelcic
  @desc <pre>

This software is distributed under the BSD license.

Copyright (c) 2022, Primoz Gabrijelcic
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
- The name of the Primoz Gabrijelcic may not be used to endorse or promote
  products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

  Author           : Primoz Gabrijelcic
  Creation date    : 2022-02-28
  Last modification: 2022-02-28
  Version          : 1.0

  </pre>}{

  History:
    1.0: 2022-02-28
      - Released.
}

// https://docs.microsoft.com/en-us/windows/win32/sync/condition-variables
// https://pubs.opengroup.org/onlinepubs/7908799/xsh/pthread_cond_timedwait.html
// https://pubs.opengroup.org/onlinepubs/7908799/xsh/pthread_cond_signal.html

unit GpSync.CondVar;

interface

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
  Posix.SysTypes,
  Posix.Time,
{$ENDIF}
{$IFDEF MACOS}
  Macapi.CoreServices,
  Macapi.Mach,
{$ENDIF MACOS}
  System.SyncObjs,
  System.SysUtils;

type
  TLightweightCondVar = record
{$IFDEF MACOS}
  private
    class var CalendarClock: clock_serv_t;
{$ENDIF MACOS}
  private
{$IFDEF MSWINDOWS}
    FNativeCV: TRTLConditionVariable;
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
    FNativeCV: pthread_cond_t;
    procedure GetPosixEndTime(var EndTime: timespec; TimeOut: Cardinal);
{$ENDIF POSIX}
  public
{$IFDEF MACOS}
    class constructor Create;
    class destructor Destroy;
{$ENDIF MACOS}
    class operator Initialize(out Dest: TLightweightCondVar);
    class operator Finalize(var Dest: TLightweightCondVar);
    procedure Broadcast;
    procedure Signal;
{$IFDEF MSWINDOWS}
    procedure Wait(var CS: TRTLCriticalSection); overload;
    procedure Wait(CS: TCriticalSection); overload;
    procedure Wait(var SRW: SRWLOCK; Flags: Cardinal = 0); overload;
    procedure Wait(const SRW: TLightweightMREW; Flags: Cardinal = 0); overload;
    function TryWait(var CS: TRTLCriticalSection; Timeout: Cardinal): boolean; overload;
    function TryWait(CS: TCriticalSection; Timeout: Cardinal): boolean; overload;
    function TryWait(var SRW: SRWLOCK; Timeout: Cardinal; Flags: Cardinal): boolean; overload;
    function TryWait(const SRW: TLightweightMREW; Timeout: Cardinal; Flags: Cardinal): boolean; overload;
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
    procedure Wait(var mutex: pthread_mutex_t); overload;
    procedure Wait(mutex: TMutex); overload;
    function TryWait(var mutex: pthread_mutex_t; Timeout: Cardinal): boolean; overload;
    function TryWait(mutex: TMutex; Timeout: Cardinal): boolean; overload;
{$ENDIF POSIX}
  end;

  TLockConditionVariable = record
  private
    FCondVar: TLightweightCondVar;
{$IFDEF MSWINDOWS}
    FSRW    : TLightweightMREW;
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
    FMutex  : pthread_mutex_t;
{$ENDIF POSIX}
  public
{$IFDEF POSIX}
    class operator Initialize(out Dest: TLockConditionVariable);
    class operator Finalize(var Dest: TLockConditionVariable);
{$ENDIF POSIX}
    procedure Acquire; inline;
    procedure Release; inline;
    procedure Broadcast; inline;
    procedure Signal; inline;
    procedure Wait; inline;
    function TryWait(Timeout: Cardinal): boolean; inline;
  end;

implementation

{$IFDEF POSIX}
uses
  Posix.PThread,
  Posix.Errno;
{$ENDIF POSIX}

{$IFDEF MSWINDOWS}
type
  TCSHelper = class helper for TCriticalSection
  private
  type
    PRTLCriticalSection = ^TRTLCriticalSection;
    function GetNativeCS: PRTLCriticalSection; inline;
  public
    property NativeCS: PRTLCriticalSection read GetNativeCS;
  end;

  TSRWHelper = record helper for TLightweightMREW
  private
  type
    PSRWLOCK = ^SRWLOCK;
    function GetNativeRW: PSRWLOCK; inline;
  public
    property NativeRW: PSRWLOCK read GetNativeRW;
  end;

{ TSRWHelper }

function TSRWHelper.GetNativeRW: PSRWLOCK;
begin
  Result := PSRWLOCK(@Self);
end;

{ TCSHelper }

function TCSHelper.GetNativeCS: PRTLCriticalSection;
begin
  Result := PRTLCriticalSection(NativeUInt(Self) + SizeOf(pointer));
end;
{$ENDIF MSWINDOWS}

{$IFDEF POSIX}
type
  TMutexHelper = class helper for TMutex
  private
  type
    ppthread_mutex_t = ^pthread_mutex_t;
    function GetNativeMutex: ppthread_mutex_t;
  public
    property NativeMutex: ppthread_mutex_t read GetNativeMutex;
  end;

function TMutexHelper.GetNativeMutex: ppthread_mutex_t;
begin
  Result := ppthread_mutex_t(NativeUInt(Self) + SizeOf(pointer));
end;
{$ENDIF}

{ TLightweightCondVar }

{$IFDEF MACOS}
class constructor TLightweightCondVar.Create;
begin
  host_get_clock_service(mach_host_self, CALENDAR_CLOCK, CalendarClock);
end;

class destructor TLightweightCondVar.Destroy;
begin
  mach_port_deallocate(mach_task_self, CalendarClock);
end;
{$ENDIF MACOS}

class operator TLightweightCondVar.Initialize(out Dest: TLightweightCondVar);
begin
{$IFDEF MSWINDOWS}
  InitializeConditionVariable(Dest.FNativeCV);
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
  CheckOSError(pthread_cond_init(Dest.FNativeCV, nil));
{$ENDIF POSIX}
end;

class operator TLightweightCondVar.Finalize(var Dest: TLightweightCondVar);
begin
{$IFDEF POSIX}
  CheckOSError(pthread_cond_destroy(Dest.FNativeCV));
{$ENDIF POSIX}
end;

{$IFDEF POSIX}
procedure TLightweightCondVar.GetPosixEndTime(var EndTime: timespec; TimeOut: Cardinal);
{$IFDEF MACOS}
var
  Now: mach_timespec_t;
  NanoSecTimeout: Int64;
begin
  clock_get_time(CalendarClock, Now);
{$ELSE}
var
  Now: timespec;
  NanoSecTimeout: Int64;
begin
  CheckOSError(clock_gettime(CLOCK_REALTIME, @Now));
{$ENDIF MACOS}
  NanoSecTimeout := Now.tv_nsec + (Int64(Timeout) * 1000000);
  EndTime.tv_sec := Int32(Now.tv_sec) + Int32(NanoSecTimeout div 1000000000);
  EndTime.tv_nsec := Int32(NanoSecTimeout mod 1000000000);
end;
{$ENDIF POSIX}

procedure TLightweightCondVar.Broadcast;
begin
{$IFDEF MSWINDOWS}
  WakeAllConditionVariable(FNativeCV);
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
  CheckOSError(pthread_cond_broadcast(FNativeCV));
{$ENDIF POSIX}
end;

procedure TLightweightCondVar.Signal;
begin
{$IFDEF MSWINDOWS}
  WakeConditionVariable(FNativeCV);
{$ENDIF MSWINDOWS}
{$IFDEF POSIX}
  CheckOSError(pthread_cond_signal(FNativeCV));
{$ENDIF POSIX}
end;

{$IFDEF MSWINDOWS}
function TLightweightCondVar.TryWait(var CS: TRTLCriticalSection; Timeout: Cardinal): boolean;
begin
  Result := SleepConditionVariableCS(FNativeCV, CS, Timeout);
  if (not Result) and (GetLastError <> ERROR_TIMEOUT) then
    RaiseLastOSError;
end;

function TLightweightCondVar.TryWait(CS: TCriticalSection; Timeout: Cardinal): boolean;
begin
  Result := SleepConditionVariableCS(FNativeCV, CS.NativeCS^, Timeout);
  if (not Result) and (GetLastError <> ERROR_TIMEOUT) then
    RaiseLastOSError;
end;

function TLightweightCondVar.TryWait(var SRW: SRWLOCK; Timeout: Cardinal; Flags: Cardinal): boolean;
begin
  Result := SleepConditionVariableSRW(FNativeCV, SRW, Timeout, Flags);
  if (not Result) and (GetLastError <> ERROR_TIMEOUT) then
    RaiseLastOSError;
end;

function TLightweightCondVar.TryWait(const SRW: TLightweightMREW; Timeout: Cardinal; Flags: Cardinal): boolean;
begin
  Result := SleepConditionVariableSRW(FNativeCV, SRW.NativeRW^, Timeout, Flags);
  if (not Result) and (GetLastError <> ERROR_TIMEOUT) then
    RaiseLastOSError;
end;
{$ENDIF MSWINDOWS}

{$IFDEF POSIX}
function TLightweightCondVar.TryWait(var mutex: pthread_mutex_t; Timeout: Cardinal): boolean;
var
  Err: Integer;
  EndTime: timespec;
begin
  if Timeout < INFINITE then begin
    GetPosixEndTime(EndTime, Timeout);
    Err := pthread_cond_timedwait(FNativeCV, mutex, EndTime);
    Result := Err = 0;
    if (not Result) and (Err <> ETIMEDOUT) then
      CheckOSError(Err);
  end
  else begin
    CheckOSError(pthread_cond_wait(FNativeCV, mutex));
    Result := true;
  end;
end;

function TLightweightCondVar.TryWait(mutex: TMutex; Timeout: Cardinal): boolean;
begin
  Result := TryWait(mutex.NativeMutex^, Timeout);
end;
{$ENDIF POSIX}

{$IFDEF MSWINDOWS}
procedure TLightweightCondVar.Wait(var CS: TRTLCriticalSection);
begin
  if not SleepConditionVariableCS(FNativeCV, CS, INFINITE) then
    RaiseLastOSError;
end;

procedure TLightweightCondVar.Wait(CS: TCriticalSection);
begin
  if not SleepConditionVariableCS(FNativeCV, CS.NativeCS^, INFINITE) then
    RaiseLastOSError;
end;

procedure TLightweightCondVar.Wait(var SRW: SRWLOCK; Flags: Cardinal);
begin
  if not SleepConditionVariableSRW(FNativeCV, SRW, INFINITE, Flags) then
    RaiseLastOSError;
end;

procedure TLightweightCondVar.Wait(const SRW: TLightweightMREW; Flags: Cardinal);
begin
  if not SleepConditionVariableSRW(FNativeCV, SRW.NativeRW^, INFINITE, Flags) then
    RaiseLastOSError;
end;
{$ENDIF MSWINDOWS}

{$IFDEF POSIX}
procedure TLightweightCondVar.Wait(var mutex: pthread_mutex_t);
begin
  CheckOSError(pthread_cond_wait(FNativeCV, mutex));
end;

procedure TLightweightCondVar.Wait(mutex: TMutex);
begin
  CheckOSError(pthread_cond_wait(FNativeCV, mutex.NativeMutex^));
end;
{$ENDIF POSIX}

{ TLockConditionVariable }

{$IFDEF POSIX}
class operator TLockConditionVariable.Initialize(out Dest: TLockConditionVariable);
var
  attr: pthread_mutexattr_t;
begin
  CheckOSError(pthread_mutexattr_init(attr));
  CheckOSError(pthread_mutexattr_settype(attr, PTHREAD_MUTEX_RECURSIVE));
  CheckOSError(pthread_mutex_init(Dest.FMutex, attr));
  CheckOSError(pthread_mutexattr_destroy(attr));
end;

class operator TLockConditionVariable.Finalize(var Dest: TLockConditionVariable);
begin
  pthread_mutex_destroy(Dest.FMutex);
end;
{$ENDIF POSIX}

procedure TLockConditionVariable.Acquire;
begin
  {$IFDEF MSWINDOWS}
  FSRW.BeginWrite;
  {$ENDIF MSWINDOWS}
  {$IFDEF POSIX}
  CheckOSError(pthread_mutex_lock(FMutex));
  {$ENDIF POSIX}
end;

procedure TLockConditionVariable.Broadcast;
begin
  FCondVar.Broadcast;
end;

procedure TLockConditionVariable.Release;
begin
  {$IFDEF MSWINDOWS}
  FSRW.EndWrite;
  {$ENDIF MSWINDOWS}
  {$IFDEF POSIX}
  CheckOSError(pthread_mutex_unlock(FMutex));
  {$ENDIF POSIX}
end;

procedure TLockConditionVariable.Signal;
begin
  FCondVar.Signal;
end;

function TLockConditionVariable.TryWait(Timeout: Cardinal): boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := FCondVar.TryWait(FSRW, Timeout, 0);
  {$ENDIF MSWINDOWS}
  {$IFDEF POSIX}
  Result := FCondVar.TryWait(FMutex, Timeout);
  {$ENDIF POSIX}
end;

procedure TLockConditionVariable.Wait;
begin
  {$IFDEF MSWINDOWS}
  FCondVar.Wait(FSRW, 0);
  {$ENDIF MSWINDOWS}
  {$IFDEF POSIX}
  FCondVar.Wait(FMutex);
  {$ENDIF POSIX}
end;

end.
