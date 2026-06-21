package com.linkvault.modules.quota.service;

import com.linkvault.common.exception.BusinessException;
import com.linkvault.modules.quota.domain.UserQuotaEntity;
import com.linkvault.modules.quota.dto.QuotaVM;
import com.linkvault.modules.quota.repository.UserQuotaRepository;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class QuotaService {
    private final UserQuotaRepository quotaRepository;

    public QuotaService(UserQuotaRepository quotaRepository) {
        this.quotaRepository = quotaRepository;
    }

    @Transactional
    public QuotaVM initializeQuota(UUID userId) {
        var quota = quotaRepository.findByUserId(userId)
                .orElseGet(() -> quotaRepository.save(UserQuotaEntity.createDefault(userId)));
        return toVm(quota);
    }

    @Transactional(readOnly = true)
    public QuotaVM getQuota(UUID userId) {
        return toVm(quotaRepository.getByUserId(userId));
    }

    @Transactional(readOnly = true)
    public void checkCanUpload(UUID userId, long bytes) {
        var quota = quotaRepository.getByUserId(userId);
        if (bytes < 0 || quota.getAvailableBytes() < bytes) {
            throw new BusinessException("quota_exceeded", "Storage quota exceeded", HttpStatus.UNPROCESSABLE_ENTITY);
        }
    }

    @Transactional
    public QuotaVM commitUpload(UUID userId, long bytes) {
        var quota = quotaRepository.getByUserId(userId);
        quota.commitUpload(bytes);
        return toVm(quota);
    }

    @Transactional
    public QuotaVM releaseUsedBytes(UUID userId, long bytes) {
        var quota = quotaRepository.getByUserId(userId);
        quota.releaseUsedBytes(bytes);
        return toVm(quota);
    }

    private QuotaVM toVm(UserQuotaEntity quota) {
        var ratio = quota.getTotalBytes() == 0
                ? 0
                : (double) quota.getUsedBytes() / (double) quota.getTotalBytes();
        return new QuotaVM(quota.getTotalBytes(), quota.getUsedBytes(), quota.getAvailableBytes(), ratio);
    }
}
