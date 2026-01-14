/**
 * @file AudioRecordSDK.h
 * @brief AudioRecordKit C API - macOS 音频录制 SDK
 * 
 * 提供跨语言的 C 接口，支持 Chromium (C++)、Electron (Node.js) 等调用场景。
 * 
 * @version 1.0.0
 * @date 2026-01-07
 * 
 * 系统要求:
 * - macOS 13.0+ (基础功能)
 * - macOS 14.4+ (进程音频录制 / Process Tap)
 * 
 * 权限要求:
 * - NSMicrophoneUsageDescription (麦克风)
 * - 屏幕录制权限 (系统音频)
 */

#ifndef AUDIO_RECORD_SDK_H
#define AUDIO_RECORD_SDK_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// MARK: - 类型定义
// ============================================================================

/**
 * @brief SDK 句柄类型（不透明指针）
 */
typedef void* AudioRecordHandle;

/**
 * @brief 录制模式
 */
typedef enum {
    AudioRecordMode_Microphone = 0,      ///< 纯麦克风录制
    AudioRecordMode_SystemAudio = 1,     ///< 系统音频录制
    AudioRecordMode_SpecificProcess = 2, ///< 特定进程音频录制
    AudioRecordMode_Mixed = 3            ///< 麦克风 + 系统音频混音
} AudioRecordMode;

/**
 * @brief 音频格式
 */
typedef enum {
    AudioFormat_M4A = 0,   ///< AAC 编码的 M4A
    AudioFormat_WAV = 1,   ///< 无损 WAV
    AudioFormat_CAF = 2    ///< Core Audio Format
} AudioFormat;

/**
 * @brief 录制状态
 */
typedef enum {
    AudioRecordState_Idle = 0,       ///< 空闲
    AudioRecordState_Preparing = 1,  ///< 准备中
    AudioRecordState_Recording = 2,  ///< 录制中
    AudioRecordState_Stopping = 3,   ///< 停止中
    AudioRecordState_Paused = 4      ///< 已暂停
} AudioRecordState;

/**
 * @brief 错误码
 */
typedef enum {
    AudioRecordError_None = 0,                ///< 无错误
    AudioRecordError_InvalidHandle = -1,      ///< 无效句柄
    AudioRecordError_PermissionDenied = -2,   ///< 权限被拒绝
    AudioRecordError_AlreadyRecording = -3,   ///< 已在录制中
    AudioRecordError_NotRecording = -4,       ///< 未在录制
    AudioRecordError_DeviceError = -5,        ///< 设备错误
    AudioRecordError_FileError = -6,          ///< 文件错误
    AudioRecordError_UnsupportedMode = -7,    ///< 不支持的模式
    AudioRecordError_SystemVersionTooLow = -8,///< 系统版本过低
    AudioRecordError_Unknown = -99            ///< 未知错误
} AudioRecordError;

/**
 * @brief 权限状态
 */
typedef enum {
    AudioPermission_NotDetermined = 0,  ///< 未确定
    AudioPermission_Granted = 1,        ///< 已授权
    AudioPermission_Denied = 2,         ///< 已拒绝
    AudioPermission_Restricted = 3      ///< 受限制
} AudioPermissionStatus;

/**
 * @brief 进程信息
 */
typedef struct {
    int32_t pid;                 ///< 进程 ID
    const char* name;            ///< 进程名称
    const char* bundleID;        ///< Bundle ID
    const char* path;            ///< 可执行文件路径
} AudioProcessInfo;

/**
 * @brief 进程列表
 */
typedef struct {
    AudioProcessInfo* processes;  ///< 进程数组
    int32_t count;               ///< 进程数量
} AudioProcessList;

// ============================================================================
// MARK: - 回调类型定义
// ============================================================================

/**
 * @brief 音频电平回调
 * @param level 电平值 (0.0 - 1.0)
 * @param userData 用户数据
 */
typedef void (*AudioLevelCallback)(float level, void* userData);

/**
 * @brief 录制状态变化回调
 * @param state 新状态
 * @param userData 用户数据
 */
typedef void (*AudioStateCallback)(AudioRecordState state, void* userData);

/**
 * @brief 录制完成回调
 * @param filePath 录制文件路径 (UTF-8 编码)
 * @param durationMs 录制时长（毫秒）
 * @param userData 用户数据
 */
typedef void (*AudioCompleteCallback)(const char* filePath, int64_t durationMs, void* userData);

/**
 * @brief 错误回调
 * @param error 错误码
 * @param message 错误消息 (UTF-8 编码)
 * @param userData 用户数据
 */
typedef void (*AudioErrorCallback)(AudioRecordError error, const char* message, void* userData);

// ============================================================================
// MARK: - 生命周期管理
// ============================================================================

/**
 * @brief 创建 SDK 实例
 * @return 句柄，失败返回 NULL
 */
AudioRecordHandle AudioRecord_Create(void);

/**
 * @brief 销毁 SDK 实例
 * @param handle SDK 句柄
 */
void AudioRecord_Destroy(AudioRecordHandle handle);

/**
 * @brief 获取 SDK 版本
 * @return 版本字符串 (例如 "1.0.0")
 */
const char* AudioRecord_GetVersion(void);

// ============================================================================
// MARK: - 录制控制
// ============================================================================

/**
 * @brief 开始录制
 * @param handle SDK 句柄
 * @param mode 录制模式
 * @return 错误码
 */
AudioRecordError AudioRecord_Start(AudioRecordHandle handle, AudioRecordMode mode);

/**
 * @brief 开始录制（指定进程）
 * @param handle SDK 句柄
 * @param pid 目标进程 ID
 * @return 错误码
 */
AudioRecordError AudioRecord_StartWithProcess(AudioRecordHandle handle, int32_t pid);

/**
 * @brief 停止录制
 * @param handle SDK 句柄
 * @return 错误码
 */
AudioRecordError AudioRecord_Stop(AudioRecordHandle handle);

/**
 * @brief 暂停录制
 * @param handle SDK 句柄
 * @return 错误码
 */
AudioRecordError AudioRecord_Pause(AudioRecordHandle handle);

/**
 * @brief 恢复录制
 * @param handle SDK 句柄
 * @return 错误码
 */
AudioRecordError AudioRecord_Resume(AudioRecordHandle handle);

/**
 * @brief 检查是否正在录制
 * @param handle SDK 句柄
 * @return true 表示正在录制
 */
bool AudioRecord_IsRecording(AudioRecordHandle handle);

/**
 * @brief 获取当前录制状态
 * @param handle SDK 句柄
 * @return 录制状态
 */
AudioRecordState AudioRecord_GetState(AudioRecordHandle handle);

/**
 * @brief 获取当前录制时长
 * @param handle SDK 句柄
 * @return 时长（毫秒）
 */
int64_t AudioRecord_GetDuration(AudioRecordHandle handle);

// ============================================================================
// MARK: - 配置
// ============================================================================

/**
 * @brief 设置音频格式
 * @param handle SDK 句柄
 * @param format 音频格式
 * @return 错误码
 */
AudioRecordError AudioRecord_SetFormat(AudioRecordHandle handle, AudioFormat format);

/**
 * @brief 设置采样率
 * @param handle SDK 句柄
 * @param sampleRate 采样率 (例如 44100, 48000)
 * @return 错误码
 */
AudioRecordError AudioRecord_SetSampleRate(AudioRecordHandle handle, int32_t sampleRate);

/**
 * @brief 设置输出目录
 * @param handle SDK 句柄
 * @param path 目录路径 (UTF-8 编码)
 * @return 错误码
 */
AudioRecordError AudioRecord_SetOutputDirectory(AudioRecordHandle handle, const char* path);

// ============================================================================
// MARK: - 回调设置
// ============================================================================

/**
 * @brief 设置电平回调
 * @param handle SDK 句柄
 * @param callback 回调函数
 * @param userData 用户数据
 */
void AudioRecord_SetLevelCallback(AudioRecordHandle handle, AudioLevelCallback callback, void* userData);

/**
 * @brief 设置状态变化回调
 * @param handle SDK 句柄
 * @param callback 回调函数
 * @param userData 用户数据
 */
void AudioRecord_SetStateCallback(AudioRecordHandle handle, AudioStateCallback callback, void* userData);

/**
 * @brief 设置录制完成回调
 * @param handle SDK 句柄
 * @param callback 回调函数
 * @param userData 用户数据
 */
void AudioRecord_SetCompleteCallback(AudioRecordHandle handle, AudioCompleteCallback callback, void* userData);

/**
 * @brief 设置错误回调
 * @param handle SDK 句柄
 * @param callback 回调函数
 * @param userData 用户数据
 */
void AudioRecord_SetErrorCallback(AudioRecordHandle handle, AudioErrorCallback callback, void* userData);

// ============================================================================
// MARK: - 权限管理
// ============================================================================

/**
 * @brief 检查麦克风权限
 * @return 权限状态
 */
AudioPermissionStatus AudioRecord_GetMicrophonePermission(void);

/**
 * @brief 请求麦克风权限
 * @param callback 结果回调
 * @param userData 用户数据
 */
void AudioRecord_RequestMicrophonePermission(void (*callback)(AudioPermissionStatus status, void* userData), void* userData);

/**
 * @brief 检查屏幕录制权限（系统音频）
 * @return 权限状态
 */
AudioPermissionStatus AudioRecord_GetScreenCapturePermission(void);

// ============================================================================
// MARK: - 进程枚举
// ============================================================================

/**
 * @brief 进程列表句柄类型（不透明指针）
 */
typedef void* AudioProcessListHandle;

/**
 * @brief 获取可录制的音频进程数量（快速检查）
 * @return 进程数量
 */
int32_t AudioRecord_GetAudioProcessCount(void);

/**
 * @brief 获取可录制的音频进程列表
 * @return 进程列表句柄，使用后需调用 AudioRecord_FreeProcessList 释放
 */
AudioProcessListHandle AudioRecord_GetAudioProcesses(void);

/**
 * @brief 获取进程列表中的进程数量
 * @param handle 进程列表句柄
 * @return 进程数量
 */
int32_t AudioRecord_GetProcessListCount(AudioProcessListHandle handle);

/**
 * @brief 获取指定索引的进程 PID
 * @param handle 进程列表句柄
 * @param index 进程索引
 * @return 进程 PID，失败返回 -1
 */
int32_t AudioRecord_GetProcessPID(AudioProcessListHandle handle, int32_t index);

/**
 * @brief 获取指定索引的进程名称
 * @param handle 进程列表句柄
 * @param index 进程索引
 * @return 进程名称 (UTF-8)，失败返回 NULL
 */
const char* AudioRecord_GetProcessName(AudioProcessListHandle handle, int32_t index);

/**
 * @brief 获取指定索引的进程 Bundle ID
 * @param handle 进程列表句柄
 * @param index 进程索引
 * @return Bundle ID (UTF-8)，失败返回 NULL
 */
const char* AudioRecord_GetProcessBundleID(AudioProcessListHandle handle, int32_t index);

/**
 * @brief 释放进程列表
 * @param handle 进程列表句柄
 */
void AudioRecord_FreeProcessList(AudioProcessListHandle handle);

// ============================================================================
// MARK: - 工具函数
// ============================================================================

/**
 * @brief 获取错误描述
 * @param error 错误码
 * @return 错误描述字符串
 */
const char* AudioRecord_GetErrorDescription(AudioRecordError error);

/**
 * @brief 检查系统是否支持指定模式
 * @param mode 录制模式
 * @return true 表示支持
 */
bool AudioRecord_IsModeSupported(AudioRecordMode mode);

#ifdef __cplusplus
}
#endif

#endif // AUDIO_RECORD_SDK_H

