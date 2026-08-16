import { SetMetadata } from '@nestjs/common';
import { RoleUtilisateur } from '../../entities/utilisateur.entity';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: RoleUtilisateur[]) => SetMetadata(ROLES_KEY, roles);
