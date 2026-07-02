import 'package:climate_storyteller/features/climate_data/data/datasources/climate_local_data_source.dart';
import 'package:climate_storyteller/features/climate_data/data/datasources/climate_remote_data_source.dart';
import 'package:climate_storyteller/features/climate_data/data/datasources/aqi_remote_data_source.dart';
import 'package:climate_storyteller/features/climate_data/data/datasources/forest_remote_data_source.dart';
import 'package:climate_storyteller/features/climate_data/data/repositories/climate_repository_impl.dart';
import 'package:climate_storyteller/features/climate_data/data/repositories/aqi_repository_impl.dart';
import 'package:climate_storyteller/features/climate_data/data/repositories/forest_repository_impl.dart';
import 'package:climate_storyteller/features/climate_data/domain/repositories/climate_repository.dart';
import 'package:climate_storyteller/features/climate_data/domain/repositories/aqi_repository.dart';
import 'package:climate_storyteller/features/climate_data/domain/repositories/forest_repository.dart';
import 'package:climate_storyteller/features/climate_data/domain/usecases/get_climate_stats.dart';
import 'package:climate_storyteller/features/climate_data/domain/usecases/get_aqi_data.dart';
import 'package:climate_storyteller/features/climate_data/domain/usecases/get_forest_data.dart';
import 'package:climate_storyteller/features/narrator/data/datasources/narrator_remote_data_source.dart';
import 'package:climate_storyteller/features/narrator/data/datasources/tts_data_source.dart';
import 'package:climate_storyteller/features/narrator/data/repositories/narrator_repository_impl.dart';
import 'package:climate_storyteller/features/narrator/domain/repositories/narrator_repository.dart';
import 'package:climate_storyteller/features/narrator/domain/usecases/get_narration.dart';
import 'package:climate_storyteller/features/narrator/domain/usecases/synthesize_audio.dart';
import 'package:climate_storyteller/features/lg_connection/data/datasources/lg_ssh_data_source.dart';
import 'package:climate_storyteller/features/lg_connection/data/datasources/kml_generator_data_source.dart';
import 'package:climate_storyteller/features/lg_connection/data/repositories/lg_repository_impl.dart';
import 'package:climate_storyteller/features/lg_connection/domain/repositories/lg_repository.dart';
import 'package:climate_storyteller/features/lg_connection/domain/usecases/connect_to_lg.dart';
import 'package:climate_storyteller/features/lg_connection/domain/usecases/disconnect_from_lg.dart';
import 'package:climate_storyteller/features/lg_connection/domain/usecases/send_kml_to_lg.dart';
import 'package:climate_storyteller/features/lg_connection/domain/usecases/fly_to_lg.dart';
import 'package:climate_storyteller/features/lg_connection/domain/usecases/clear_lg_kmls.dart';
import 'package:climate_storyteller/features/lg_connection/domain/usecases/relaunch_lg_earth.dart';

class DI {
  DI._();

  // Data sources
  static final climateLocalDataSource = ClimateLocalDataSourceImpl();
  static final climateRemoteDataSource = ClimateRemoteDataSourceImpl();
  static final aqiRemoteDataSource = AqiRemoteDataSourceImpl();
  static final forestRemoteDataSource = ForestRemoteDataSourceImpl();
  static final narratorRemoteDataSource = NarratorRemoteDataSourceImpl();
  static final ttsDataSource = TtsDataSourceImpl();
  static final lgSshDataSource = LgSshDataSourceImpl();
  static final kmlGeneratorDataSource = KmlGeneratorDataSourceImpl();

  // Repositories
  static final LgRepository lgRepository = LgRepositoryImpl(
    sshDataSource: lgSshDataSource,
  );
  static final ClimateRepository climateRepository = ClimateRepositoryImpl(
    remoteDataSource: climateRemoteDataSource,
    localDataSource: climateLocalDataSource,
  );
  static final AqiRepository aqiRepository = AqiRepositoryImpl(
    remoteDataSource: aqiRemoteDataSource,
  );
  static final ForestRepository forestRepository = ForestRepositoryImpl(
    remoteDataSource: forestRemoteDataSource,
    lgRepository: lgRepository,
  );
  static final NarratorRepository narratorRepository = NarratorRepositoryImpl(
    remoteDataSource: narratorRemoteDataSource,
    ttsDataSource: ttsDataSource,
  );

  // Use cases
  static final getClimateStats = GetClimateStats(climateRepository);
  static final getAqiData = GetAqiData(aqiRepository);
  static final getForestData = GetForestData(forestRepository);
  static final getNarration = GetNarration(narratorRepository);
  static final synthesizeAudio = SynthesizeAudio(narratorRepository);
  static final connectToLg = ConnectToLg(lgRepository);
  static final disconnectFromLg = DisconnectFromLg(lgRepository);
  static final sendKmlToLg = SendKmlToLg(lgRepository);
  static final flyToLg = FlyToLg(lgRepository);
  static final clearLgKmls = ClearLgKmls(lgRepository);
  static final relaunchLgEarth = RelaunchLgEarth(lgRepository);
}
