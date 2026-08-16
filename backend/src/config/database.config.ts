import { TypeOrmModuleOptions } from '@nestjs/typeorm';
import * as entities from '../entities';

export const databaseConfig = (): TypeOrmModuleOptions => ({
  type: 'postgres',
  host: process.env.DATABASE_HOST,
  port: parseInt(process.env.DATABASE_PORT ?? '5432', 10),
  username: process.env.DATABASE_USER,
  password: process.env.DATABASE_PASSWORD,
  database: process.env.DATABASE_NAME,
  entities: Object.values(entities),
  // Le schéma est piloté par les migrations SQL de yalla-backend/database/migrations,
  // pas par TypeORM : synchronize doit rester à false pour ne jamais dériver du schéma
  // validé (trigger de rupture automatique, colonnes geography, etc.).
  synchronize: false,
  logging: process.env.NODE_ENV !== 'production',
});
