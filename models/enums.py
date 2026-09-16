from enum import Enum
class UserRole(str, Enum):
    ADMIN = "admin"
    LOCADOR = "locador"
    CLIENTE = "cliente"


class TenantStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"


class ItemStatus(str, Enum):
    AVAILABLE = "available"
    UNAVAILABLE = "unavailable"
    MAINTENANCE = "maintenance"


class BookingStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"
    COMPLETED = "completed"