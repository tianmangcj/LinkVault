package com.linkvault.modules.users.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import org.springframework.security.crypto.password.PasswordEncoder;

@Entity
@Table(name = "users")
public class UserEntity extends BaseEntity {
    private static final String USERNAME_PATTERN = "^[A-Za-z0-9]+$";

    @Column(name = "username", nullable = false, unique = true, length = 64)
    private String username;

    @Column(name = "email", unique = true, length = 160)
    private String email;

    @Column(name = "password_hash", nullable = false, length = 120)
    private String passwordHash;

    @Column(name = "display_name", nullable = false, length = 80)
    private String displayName;

    @Column(name = "avatar_text", nullable = false, length = 4)
    private String avatarText;

    @Column(name = "avatar_image_data")
    private String avatarImageData;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 24)
    private UserRole role;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private UserStatus status;

    protected UserEntity() {
    }

    private UserEntity(String username, String passwordHash) {
        this.username = normalizeUsername(username);
        this.passwordHash = passwordHash;
        this.displayName = this.username;
        this.avatarText = defaultAvatarText(this.username);
        this.role = UserRole.USER;
        this.status = UserStatus.ACTIVE;
    }

    public static UserEntity create(String username, String passwordHash) {
        return new UserEntity(username, passwordHash);
    }

    public boolean passwordMatches(PasswordEncoder encoder, String rawPassword) {
        return encoder.matches(rawPassword, passwordHash);
    }

    public void updateProfile(String displayName, String avatarText) {
        if (displayName != null && !displayName.isBlank()) {
            this.displayName = displayName.trim();
        }
        if (avatarText != null && !avatarText.isBlank()) {
            this.avatarText = avatarText.trim();
        }
    }

    public void changeUsername(String username) {
        this.username = normalizeUsername(username);
    }

    public void updateAvatarImage(String avatarImageData) {
        this.avatarImageData = avatarImageData;
    }

    public void changePassword(String passwordHash) {
        if (passwordHash == null || passwordHash.isBlank()) {
            throw new IllegalArgumentException("passwordHash is required");
        }
        this.passwordHash = passwordHash;
    }

    public void disable() {
        this.status = UserStatus.DISABLED;
    }

    public boolean isActive() {
        return status == UserStatus.ACTIVE;
    }

    public String getUsername() {
        return username;
    }

    public String getEmail() {
        return email;
    }

    public String getDisplayName() {
        return displayName;
    }

    public String getAvatarText() {
        return avatarText;
    }

    public String getAvatarImageData() {
        return avatarImageData;
    }

    public UserRole getRole() {
        return role;
    }

    public UserStatus getStatus() {
        return status;
    }

    private static String normalizeUsername(String username) {
        if (username == null || username.isBlank()) {
            throw new IllegalArgumentException("username is required");
        }
        var normalized = username.trim();
        if (!normalized.matches(USERNAME_PATTERN)) {
            throw new IllegalArgumentException("username may only contain English letters and numbers");
        }
        return normalized;
    }

    private static String defaultAvatarText(String username) {
        return username.substring(0, 1).toUpperCase();
    }
}
