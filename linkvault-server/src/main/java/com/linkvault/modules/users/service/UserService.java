package com.linkvault.modules.users.service;

import com.linkvault.common.exception.ConflictException;
import com.linkvault.common.exception.BusinessException;
import com.linkvault.modules.auth.repository.RefreshTokenRepository;
import com.linkvault.modules.devices.repository.DeviceRepository;
import com.linkvault.modules.downloads.repository.DownloadTaskRepository;
import com.linkvault.modules.files.domain.FileNodeType;
import com.linkvault.modules.files.repository.FileNodeRepository;
import com.linkvault.modules.quota.repository.UserQuotaRepository;
import com.linkvault.modules.storage.service.StorageObjectService;
import com.linkvault.modules.transfers.repository.TransferTaskRepository;
import com.linkvault.modules.uploads.repository.FolderUploadTaskRepository;
import com.linkvault.modules.uploads.repository.UploadTaskRepository;
import com.linkvault.modules.users.domain.UserEntity;
import com.linkvault.modules.users.dto.CreateUserCmd;
import com.linkvault.modules.users.dto.UpdateProfileCmd;
import com.linkvault.modules.users.dto.UserProfileVM;
import com.linkvault.modules.users.repository.UserRepository;
import java.util.Base64;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserService {
    private static final String USERNAME_PATTERN = "^[A-Za-z0-9]+$";

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final FileNodeRepository fileNodeRepository;
    private final StorageObjectService storageObjectService;
    private final TransferTaskRepository transferTaskRepository;
    private final UploadTaskRepository uploadTaskRepository;
    private final FolderUploadTaskRepository folderUploadTaskRepository;
    private final DownloadTaskRepository downloadTaskRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final DeviceRepository deviceRepository;
    private final UserQuotaRepository userQuotaRepository;

    public UserService(
            UserRepository userRepository,
            PasswordEncoder passwordEncoder,
            FileNodeRepository fileNodeRepository,
            StorageObjectService storageObjectService,
            TransferTaskRepository transferTaskRepository,
            UploadTaskRepository uploadTaskRepository,
            FolderUploadTaskRepository folderUploadTaskRepository,
            DownloadTaskRepository downloadTaskRepository,
            RefreshTokenRepository refreshTokenRepository,
            DeviceRepository deviceRepository,
            UserQuotaRepository userQuotaRepository
    ) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.fileNodeRepository = fileNodeRepository;
        this.storageObjectService = storageObjectService;
        this.transferTaskRepository = transferTaskRepository;
        this.uploadTaskRepository = uploadTaskRepository;
        this.folderUploadTaskRepository = folderUploadTaskRepository;
        this.downloadTaskRepository = downloadTaskRepository;
        this.refreshTokenRepository = refreshTokenRepository;
        this.deviceRepository = deviceRepository;
        this.userQuotaRepository = userQuotaRepository;
    }

    @Transactional
    public UserProfileVM createUser(CreateUserCmd cmd) {
        var username = normalizeUsername(cmd.username());
        if (userRepository.existsByUsernameIgnoreCase(username)) {
            throw new ConflictException("name_conflict", "Username already exists");
        }

        var user = UserEntity.create(username, passwordEncoder.encode(cmd.rawPassword()));
        return toProfile(userRepository.save(user));
    }

    @Transactional(readOnly = true)
    public UserProfileVM getCurrentUser(UUID userId) {
        return toProfile(getUserEntity(userId));
    }

    @Transactional(readOnly = true)
    public UserEntity getUserEntity(UUID userId) {
        return userRepository.getByIdOrThrow(userId);
    }

    @Transactional
    public UserProfileVM updateProfile(UUID userId, UpdateProfileCmd cmd) {
        var user = userRepository.getByIdOrThrow(userId);
        user.updateProfile(cmd.displayName(), cmd.avatarText());
        return toProfile(user);
    }

    @Transactional
    public UserProfileVM updateUsername(UUID userId, String username) {
        var user = userRepository.getByIdOrThrow(userId);
        var normalized = normalizeUsername(username);
        if (user.getUsername().equalsIgnoreCase(normalized)) {
            user.changeUsername(normalized);
            return toProfile(user);
        }
        if (userRepository.existsByUsernameIgnoreCase(normalized)) {
            throw new ConflictException("name_conflict", "Username already exists");
        }
        user.changeUsername(normalized);
        return toProfile(user);
    }

    @Transactional
    public UserProfileVM updateAvatar(UUID userId, String avatarImageData) {
        validateAvatarImageData(avatarImageData);
        var user = userRepository.getByIdOrThrow(userId);
        user.updateAvatarImage(avatarImageData.trim());
        return toProfile(user);
    }

    @Transactional
    public void changePassword(UUID userId, String oldPassword, String newPassword, String confirmPassword) {
        if (newPassword == null || !newPassword.equals(confirmPassword)) {
            throw new BusinessException("validation_error", "New passwords do not match", HttpStatus.BAD_REQUEST);
        }
        var user = userRepository.getByIdOrThrow(userId);
        if (!user.passwordMatches(passwordEncoder, oldPassword)) {
            throw new BusinessException("invalid_password", "Old password is incorrect", HttpStatus.BAD_REQUEST);
        }
        user.changePassword(passwordEncoder.encode(newPassword));
    }

    @Transactional
    public void deleteAccount(UUID userId) {
        var user = userRepository.getByIdOrThrow(userId);
        fileNodeRepository.findByUserId(userId).stream()
                .filter(node -> node.getType() == FileNodeType.FILE)
                .map(node -> node.getStorageObjectId())
                .filter(objectId -> objectId != null)
                .forEach(storageObjectService::releaseReference);

        downloadTaskRepository.deleteByUserId(userId);
        transferTaskRepository.deleteByUserId(userId);
        uploadTaskRepository.deleteByUserId(userId);
        folderUploadTaskRepository.deleteByUserId(userId);
        fileNodeRepository.deleteByUserId(userId);
        userQuotaRepository.deleteByUserId(userId);
        refreshTokenRepository.deleteByUserId(userId);
        deviceRepository.deleteByUserId(userId);
        userRepository.delete(user);
    }

    public UserProfileVM toProfile(UserEntity user) {
        return new UserProfileVM(
                user.getId(),
                user.getUsername(),
                user.getEmail(),
                user.getDisplayName(),
                user.getAvatarText(),
                user.getAvatarImageData(),
                user.getRole().name(),
                user.getCreatedAt()
        );
    }

    private String normalizeUsername(String username) {
        if (username == null || username.isBlank()) {
            throw new BusinessException("validation_error", "Username is required", HttpStatus.BAD_REQUEST);
        }
        var normalized = username.trim();
        if (!normalized.matches(USERNAME_PATTERN)) {
            throw new BusinessException(
                    "invalid_username",
                    "Username may only contain English letters and numbers",
                    HttpStatus.BAD_REQUEST
            );
        }
        return normalized;
    }

    private void validateAvatarImageData(String avatarImageData) {
        if (avatarImageData == null || avatarImageData.isBlank()) {
            throw new BusinessException("validation_error", "Avatar image is required", HttpStatus.BAD_REQUEST);
        }
        var normalized = avatarImageData.trim();
        if (!normalized.startsWith("data:image/")) {
            throw new BusinessException("invalid_image_type", "Avatar must be an image", HttpStatus.BAD_REQUEST);
        }
        var separator = normalized.indexOf(";base64,");
        if (separator < 0 || separator < "data:image/".length()) {
            throw new BusinessException("invalid_image_type", "Avatar image format is invalid", HttpStatus.BAD_REQUEST);
        }
        var mimeType = normalized.substring("data:".length(), separator).toLowerCase();
        if (!mimeType.matches("image/[a-z0-9.+-]+")) {
            throw new BusinessException("invalid_image_type", "Avatar must be an image", HttpStatus.BAD_REQUEST);
        }
        try {
            Base64.getDecoder().decode(normalized.substring(separator + ";base64,".length()));
        } catch (IllegalArgumentException ex) {
            throw new BusinessException("invalid_image_type", "Avatar image format is invalid", HttpStatus.BAD_REQUEST);
        }
    }
}
