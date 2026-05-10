local ADDON_NAME, NS = ...
ADDON_NAME = ADDON_NAME or "MaJiang"
if type(NS) ~= "table" then
    NS = _G.MaJiangNS or {}
    _G.MaJiangNS = NS
end

local AudioModule = {}

function AudioModule.New(env)
    assert(type(env) == "table", "AudioModule.New requires env table")

    local T = assert(env.T, "AudioModule.New missing env.T")
    local GetDB = assert(env.GetDB, "AudioModule.New missing env.GetDB")
    local PrintInfo = assert(env.PrintInfo, "AudioModule.New missing env.PrintInfo")
    local CardToVoiceIndex = assert(env.CardToVoiceIndex, "AudioModule.New missing env.CardToVoiceIndex")
    local AUDIO_ROOT = assert(env.AUDIO_ROOT, "AudioModule.New missing env.AUDIO_ROOT")

    local Audio = {
        bgmPath = nil,
        bgmIndex = 0,
        bgmError = nil,
        bgmHandle = nil,
        bgmTicker = nil,
        alarmRound = nil,
    }

    local function AudioEnabledSfx()
        local db = GetDB()
        return db and db.audio and db.audio.sfxEnabled
    end

    local function AudioEnabledBgm()
        local db = GetDB()
        return db and db.audio and db.audio.bgmEnabled
    end

    local function AudioGenderPath()
        local db = GetDB()
        local g = (db and db.audio and db.audio.voiceGender) or "woman"
        if g ~= "man" then
            g = "woman"
        end
        return AUDIO_ROOT .. g .. "\\"
    end

    local function PlayAudio(path, channel)
        if not path then
            return false
        end
        local ok = PlaySoundFile(path, channel or "SFX")
        return ok and true or false
    end

    local function PlaySfx(path)
        if not AudioEnabledSfx() then
            return
        end
        PlayAudio(path, "SFX")
    end

    local function SetBgmError(msg)
        if msg and msg ~= "" and Audio.bgmError ~= msg then
            PrintInfo(msg)
        end
        Audio.bgmError = msg
    end

    local function GetMusicBlockedReason()
        if GetCVarBool and not GetCVarBool("Sound_EnableAllSound") then
            return T("系统总声音已关闭（Sound_EnableAllSound=0）")
        end
        if GetCVarBool and not GetCVarBool("Sound_EnableMusic") then
            return T("系统音乐已关闭（Sound_EnableMusic=0）")
        end
        if GetCVar then
            local vol = tonumber(GetCVar("Sound_MusicVolume") or "")
            if vol and vol <= 0 then
                return T("系统音乐音量为 0（Sound_MusicVolume=0）")
            end
        end
        return nil
    end

    local BGM_TRACKS = {
        AUDIO_ROOT .. "bgm1.mp3",
        AUDIO_ROOT .. "bgm2.mp3",
    }

    local function StopBgmHandle()
        if Audio.bgmHandle and StopSound then
            StopSound(Audio.bgmHandle, 0)
        end
        Audio.bgmHandle = nil
    end

    local function StartNextBgmTrack()
        local start = ((Audio.bgmIndex or 0) % #BGM_TRACKS) + 1
        for i = 0, #BGM_TRACKS - 1 do
            local idx = ((start + i - 1) % #BGM_TRACKS) + 1
            local pick = BGM_TRACKS[idx]
            local willPlay, soundHandle = PlaySoundFile(pick, "Music")
            if willPlay then
                Audio.bgmPath = pick
                Audio.bgmIndex = idx
                Audio.bgmHandle = soundHandle
                Audio.bgmError = nil
                return true
            end
        end
        Audio.bgmPath = nil
        Audio.bgmHandle = nil
        return false
    end

    local function IsCurrentBgmPlaying()
        if not Audio.bgmHandle then
            return false
        end
        if C_Sound and C_Sound.IsPlaying then
            local ok, playing = pcall(C_Sound.IsPlaying, Audio.bgmHandle)
            if ok then
                return playing and true or false
            end
        end
        return false
    end

    local function EnsureBgmTicker()
        if Audio.bgmTicker then
            return
        end
        Audio.bgmTicker = C_Timer.NewTicker(1.0, function()
            if not AudioEnabledBgm() then
                StopBgmHandle()
                if Audio.bgmTicker then
                    Audio.bgmTicker:Cancel()
                    Audio.bgmTicker = nil
                end
                return
            end
            local blockedReason = GetMusicBlockedReason()
            if blockedReason then
                StopBgmHandle()
                Audio.bgmPath = nil
                SetBgmError(T("背景音乐未播放：%s", blockedReason))
                return
            end
            if IsCurrentBgmPlaying() then
                return
            end
            StopBgmHandle()
            if not StartNextBgmTrack() then
                SetBgmError(T("背景音乐未播放：bgm1.mp3 / bgm2.mp3 无法打开（若刚替换音频文件，请 /reload）"))
            end
        end)
    end

    local function PlayBGM()
        if not AudioEnabledBgm() then
            return
        end
        local blockedReason = GetMusicBlockedReason()
        if blockedReason then
            Audio.bgmPath = nil
            SetBgmError(T("背景音乐未播放：%s", blockedReason))
            return
        end
        EnsureBgmTicker()
        StopBgmHandle()
        if not StartNextBgmTrack() then
            SetBgmError(T("背景音乐未播放：bgm1.mp3 / bgm2.mp3 无法打开（若刚替换音频文件，请 /reload）"))
        end
    end

    local function StopBGM()
        StopBgmHandle()
        if Audio.bgmTicker then
            Audio.bgmTicker:Cancel()
            Audio.bgmTicker = nil
        end
        StopMusic()
        Audio.bgmPath = nil
    end

    local function PlayActionVoice(actionType)
        if not AudioEnabledSfx() then
            return
        end
        local base = AudioGenderPath()
        local function playCandidates(candidates)
            local n = #candidates
            local start = math.random(1, n)
            for i = 0, n - 1 do
                local idx = ((start + i - 1) % n) + 1
                if PlayAudio(base .. candidates[idx], "SFX") then
                    return true
                end
            end
            return false
        end
        if actionType == "CHI" then
            playCandidates({ "chi1.mp3", "chi2.mp3", "chi3.mp3", "chi4.mp3" })
        elseif actionType == "PENG" then
            playCandidates({ "peng1.mp3", "peng2.mp3", "peng3.mp3", "peng4.mp3", "peng5.mp3" })
        elseif actionType == "GANG" then
            playCandidates({ "gang1.mp3", "gang2.mp3", "gang3.mp3" })
        elseif actionType == "HU" then
            playCandidates({ "hu1.mp3", "hu2.mp3", "hu3.mp3", "hu_1.mp3", "hu_2.mp3", "hu_3.mp3" })
        elseif actionType == "HU_DA" then
            playCandidates({ "hu_da1.mp3", "hu_da2.mp3", "hu_da3.mp3" })
        elseif actionType == "HU_PAO" then
            playCandidates({ "hu_pao1.mp3", "hu_pao2.mp3", "hu_pao3.mp3" })
        end
    end

    local function PlayDiscardVoice(card)
        if not AudioEnabledSfx() then
            return
        end
        local idx = CardToVoiceIndex(card)
        if not idx then
            return
        end
        local base = AudioGenderPath()
        PlayAudio(base .. "pai_" .. idx .. ".mp3", "SFX")
    end

    local function PlayCountdownAlarm()
        if not AudioEnabledSfx() then
            return
        end
        PlayAudio(AUDIO_ROOT .. "timeup_alarm.mp3", "SFX")
    end

    return {
        AudioEnabledSfx = AudioEnabledSfx,
        AudioEnabledBgm = AudioEnabledBgm,
        AudioGenderPath = AudioGenderPath,
        PlayAudio = PlayAudio,
        PlaySfx = PlaySfx,
        SetBgmError = SetBgmError,
        PlayBGM = PlayBGM,
        StopBGM = StopBGM,
        PlayActionVoice = PlayActionVoice,
        PlayDiscardVoice = PlayDiscardVoice,
        PlayCountdownAlarm = PlayCountdownAlarm,
    }
end

NS.AddonAudio = AudioModule
