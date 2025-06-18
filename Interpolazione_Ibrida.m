clc; clear; close all;
%% leggo il file
%Lettura dei dataset MAC 
fileh = 'G:\Il mio Drive\2 Tirocinio\Programma matlab\h1_main_sorted.csv'; %Sostituire con il percorso corretto...
data = readtable(fileh);
tempi_Data = datetime(data{:, 1}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
potenze_Data = data{:,2};

%Lettura dei dataset UK-DALE
% filename = 'aggregate_h2.csv';
% data = readtable(filename, 'Delimiter', ',', 'ReadVariableNames', false);
% data = rmmissing(data);
% cleanedVar1 = erase(data.Var1, '''');
% data = data(data.Var4 ~= 0, :);
% tempi_Data = datetime(data.Var1, 'InputFormat', 'yyyy-MM-dd HH:mm:ssXXX', 'TimeZone', 'UTC');
% potenze_Data=data.Var4;

%% Rimuovo le righe che presentano Nat
idx_nat = isnat(tempi_Data);
tempi_Data(idx_nat) = [];
potenze_Data(idx_nat) = [];


%% Applicazione della logica CHAIN2 e Applicazione delle etichette a ogni campione, in base al motivo per cui è stato prelevato

%Definizione parametri CHAIN2
soglie = 300:300:6000;              %Soglie di potenza
intervallo_15min = minutes(15);
tempi_Chain2 = tempi_Data(1);
potenze_Chain2 = potenze_Data(1);

tipo_chain2 = 'iniziale';           %Inizializzazione

for i = 2:length(tempi_Data)
    is_quartorario = false;
    is_soglia = false;

    %Controllo delle Quartorarie
    if tempi_Data(i) - tempi_Chain2(end) >= intervallo_15min    
        is_quartorario = true;
    else
        
        %Controllo del superamento di soglie
        for s = soglie        
            if (potenze_Data(i-1) < s && potenze_Data(i) >= s) || ...
               (potenze_Data(i-1) > s && potenze_Data(i) <= s)
                is_soglia = true;
                break;
            end
        end
    end

    if is_quartorario || is_soglia
        tempi_Chain2 = [tempi_Chain2; tempi_Data(i)];
        potenze_Chain2 = [potenze_Chain2; potenze_Data(i)];
        if is_quartorario && is_soglia
            tipo_chain2 = [tipo_chain2; "QS"];      %Gestisco anche il caso in cui un campione viene prelevato sia 
                                                    %per superamento di soglia sia per la scadenza della quartoraria
        elseif is_quartorario
            tipo_chain2 = [tipo_chain2; "Q"];
        elseif is_soglia
            tipo_chain2 = [tipo_chain2; "S"];
        end
    end
end



%% Interpolazione Next e Previous e confronto 
tempi_interpolazione=(tempi_Chain2(1):seconds(1):tempi_Chain2(end))';
y_Next=interp1(tempi_Chain2,potenze_Chain2,tempi_interpolazione,'next');
y_Previous=interp1(tempi_Chain2,potenze_Chain2,tempi_interpolazione,'previous');

%Ricampionamento --> Necessario se il segnale originale presente dei
%"buchi".
primo_tempo_chain2 =tempi_Chain2(1);
id_primo = find(tempi_Data == primo_tempo_chain2);
ultimo_tempo_chain2 = tempi_Chain2(end);
id_ultimo = find(tempi_Data == ultimo_tempo_chain2);

tempi_Dominio_tagliato=tempi_Data(id_primo:id_ultimo);
[~, idnx] = ismember(tempi_Dominio_tagliato, tempi_interpolazione);

potenze_y_Next = y_Next(idnx);                  %Potenze ricampionate NEXT
potenze_y_Previous = y_Previous(idnx);          %Potenze ricampionate PREVIOUS

potenze_Dominio_tagliato=potenze_Data(id_primo:id_ultimo); %Potenze Segnale Originale
fprintf('Finito il campionamento');



%%  CATEGORIZZARE IL TIPO DI INTERVALLI CHAIN2
% Inizializzazione
categorie_intervalli = strings(length(tempi_Chain2) - 1, 1);

for i = 1:length(tempi_Chain2)-1
    tipo_attuale = tipo_chain2{i};
    tipo_successivo = tipo_chain2{i+1};

    if tipo_attuale == "QS"  %Se il campione è del tipo QS allora lo considero come Q
        tipo_attuale = "Q"; 
    end
    if tipo_successivo == "QS"
        tipo_successivo = "Q";
    end

    % Classificazione
    if tipo_attuale == "Q" && tipo_successivo == "Q"
        categorie_intervalli(i) = "QUARTORARIA";
    elseif tipo_attuale == "Q" && tipo_successivo == "S"
        categorie_intervalli(i) = "QUARTORARIA-SOGLIA";
    elseif tipo_attuale == "S" && tipo_successivo == "Q"
        categorie_intervalli(i) = "SOGLIA-QUARTORARIA";
    elseif tipo_attuale == "S" && tipo_successivo == "S"
        categorie_intervalli(i) = "SOGLIA";
    else
        categorie_intervalli(i) = "ALTRO";  %se capita qualcosa di inatteso
    end
end
idx_quartoraria            = find(categorie_intervalli == "QUARTORARIA");
idx_quartoraria_soglia     = find(categorie_intervalli == "QUARTORARIA-SOGLIA");
idx_soglia_quartoraria     = find(categorie_intervalli == "SOGLIA-QUARTORARIA");
idx_soglia                 = find(categorie_intervalli == "SOGLIA");

%% INTERPOLAZIONE IBRIDA PREVIOUS-NEXT
clc;
% Definizione delle categorie che possono caratterizzare ciascun intervallo.
categorie = {'QUARTORARIA', 'QUARTORARIA-SOGLIA', 'SOGLIA-QUARTORARIA', 'SOGLIA'};
% Creazione di una mappa per associare a ogni categoria una
% soglia normalizzata. Questo valore rappresenta la percentuale della durata
% dell'intervallo a cui applicare il cambio di interpolazione.
% Esempio: 0.50 significa che la soglia è al 50% della durata dell'intervallo.
soglie_normalizzate = containers.Map(categorie, {0.50, 1, 0.35, 1});  %Imposto Le soglie 

interp_misto = NaN(size(tempi_Dominio_tagliato));
N = length(tempi_Chain2) - 1;
idx_corrente = 1;

for i = 1:N
    tipo_corrente = categorie_intervalli{i};
    % Controlla se la categoria esiste nella mappa delle soglie; in caso contrario, salta l'intervallo.
    if ~isKey(soglie_normalizzate, tipo_corrente)
        continue
    end
    soglia_norm = soglie_normalizzate(tipo_corrente);
    % Definisce l'inizio (t1) e la fine (t2) dell'intervallo temporale corrente
    t1 = tempi_Chain2(i);
    t2 = tempi_Chain2(i+1);
    % Salta l'iterazione se l'intervallo non è valido.
    if t2 <= t1
        continue
    end
    % Avanza l'indice 'idx_corrente' fino a raggiungere l'inizio dell'intervallo [t1, t2).
    while idx_corrente <= numel(tempi_Dominio_tagliato) && tempi_Dominio_tagliato(idx_corrente) < t1
        idx_corrente = idx_corrente + 1;
    end
    idx_start = idx_corrente;
    % Continua ad avanzare l'indice per trovare tutti i punti che cadono dentro l'intervallo.
    while idx_corrente <= numel(tempi_Dominio_tagliato) && tempi_Dominio_tagliato(idx_corrente) < t2
        idx_corrente = idx_corrente + 1;
    end
    idx_range = idx_start:idx_corrente-1;
    if isempty(idx_range)
        continue
    end

    % Applica interpolazione mista secondo la soglia della categoria
    soglia = t1 + seconds(soglia_norm * seconds(t2 - t1));  % Calcola la soglia temporale assoluta come punto percentuale all'interno dell'intervallo.
    tempo_corrente = tempi_Dominio_tagliato(idx_range);
    idx_prev = tempo_corrente < soglia;
    idx_next = ~idx_prev;

    % Applica l'interpolazione "previous" ai punti prima della soglia.
    interp_misto(idx_range(idx_prev)) = potenze_y_Previous(idx_range(idx_prev));
    % Applica l'interpolazione "next" ai punti dopo la soglia.
    interp_misto(idx_range(idx_next)) = potenze_y_Next(idx_range(idx_next));
end

% Gestisce i punti che si trovano dopo l'ultimo punto di 'tempi_Chain2'.
% Per questi punti non esiste un "next", quindi si applica sempre il "previous".
idx_finale = find(tempi_Dominio_tagliato >= tempi_Chain2(end));
interp_misto(idx_finale) = potenze_y_Previous(idx_finale);

% Filtra valori validi
idx_validi = ~isnan(interp_misto);
p_originali_validi = potenze_Dominio_tagliato(idx_validi);
tempi_validi = tempi_Dominio_tagliato(idx_validi);
potenze_y_Misto_REALE= interp_misto(idx_validi);



fprintf('METRICHE Ibrido, CASO REALE.\n');
% Calcola MAE=> Misura la media delle differenze assolute tra il segnale originale e quello interpolato.
MAE = mean(abs(p_originali_validi - potenze_y_Misto_REALE));
% Calcola RMSE=> Indica l'errore medio quadratico tra i due segnali, penalizzando maggiormente gli errori più grandi.
RMSE = sqrt(mean((p_originali_validi - potenze_y_Misto_REALE).^2));
% Calcola Pearson Correlation Coefficient (R)=> Misura la correlazione lineare tra i due segnali (tra -1 e 1).
R = corr(p_originali_validi, potenze_y_Misto_REALE, 'Type', 'Pearson');
% Calcola NRMSE=> Normalizza l'errore RMSE rispetto all'intervallo dei valori del segnale originale.
NRMSE = RMSE / (max(p_originali_validi) - min(p_originali_validi));
% Calcola Relative Error=> Esprime l'errore medio relativo in percentuale.
Relative_Error = mean(abs(p_originali_validi - potenze_y_Misto_REALE) ./ p_originali_validi) * 100;
% Salvo le metriche
metriche(1, :) = [MAE, RMSE, R, NRMSE, Relative_Error];
metrics_table1 = array2table(metriche, 'VariableNames', {'MAE', 'RMSE', 'R', 'NRMSE', 'Relative_Error %'});
disp(metrics_table1);


fprintf('METRICHE previous.\n');
% Calcola MAE=> Misura la media delle differenze assolute tra il segnale originale e quello interpolato.
MAE = mean(abs(potenze_Dominio_tagliato - potenze_y_Previous));
% Calcola RMSE=> Indica l'errore medio quadratico tra i due segnali, penalizzando maggiormente gli errori più grandi.
RMSE = sqrt(mean((potenze_Dominio_tagliato - potenze_y_Previous).^2));
% Calcola Pearson Correlation Coefficient (R)=> Misura la correlazione lineare tra i due segnali (tra -1 e 1).
R = corr(potenze_Dominio_tagliato, potenze_y_Previous, 'Type', 'Pearson');
% Calcola NRMSE=> Normalizza l'errore RMSE rispetto all'intervallo dei valori del segnale originale.
NRMSE = RMSE / (max(potenze_Dominio_tagliato) - min(potenze_Dominio_tagliato));
% Calcola Relative Error=> Esprime l'errore medio relativo in percentuale.
Relative_Error = mean(abs(potenze_Dominio_tagliato - potenze_y_Previous) ./ potenze_Dominio_tagliato) * 100;
% Salvo le metriche
metriche(1, :) = [MAE, RMSE, R, NRMSE, Relative_Error];
metrics_table = array2table(metriche, 'VariableNames', {'MAE', 'RMSE', 'R', 'NRMSE', 'Relative_Error %'});
disp(metrics_table);

%% IDEALE Interpolazione Mista Prendendo i campioni migliori di Next e di previous
% Calcolo errore assoluto
errore_Previous = abs(potenze_y_Previous - potenze_Dominio_tagliato);
errore_Next = abs(potenze_y_Next - potenze_Dominio_tagliato);

% Confronto: chi è migliore
idx_previous_migliore = find(errore_Previous < errore_Next);
idx_next_migliore = find(errore_Next < errore_Previous);
potenze_y_Misto_IDEALE=zeros(size(potenze_y_Next));
potenze_y_Misto_IDEALE(idx_next_migliore)=potenze_y_Next(idx_next_migliore);
potenze_y_Misto_IDEALE(idx_previous_migliore)=potenze_y_Previous(idx_previous_migliore);
%In alcuni casi next e previous danno la stessa stima (es in corrispondenza
%dei campioni prelevati da Chain2) allora per considerarli nel segnale
%misto aggiungo:
idx_unione = [idx_next_migliore(:); idx_previous_migliore(:)]; % li converte in colonna e poi concatena

idx_rimanenti = setdiff(1:length(potenze_y_Previous), idx_unione)';
potenze_y_Misto_IDEALE(idx_rimanenti) = potenze_y_Previous(idx_rimanenti); %Segnale Misto ideale


fprintf('METRICHE Ibrido, CASO IDEALE.\n');
%Calcolo delle metriche di errore
% Calcola MAE=> Misura la media delle differenze assolute tra il segnale originale e quello interpolato.
MAE = mean(abs(potenze_Dominio_tagliato - potenze_y_Misto_IDEALE));
% Calcola RMSE=> Indica l'errore medio quadratico tra i due segnali, penalizzando maggiormente gli errori più grandi.
RMSE = sqrt(mean((potenze_Dominio_tagliato - potenze_y_Misto_IDEALE).^2));
% Calcola Pearson Correlation Coefficient (R)=> Misura la correlazione lineare tra i due segnali (tra -1 e 1).
R = corr(potenze_Dominio_tagliato, potenze_y_Misto_IDEALE, 'Type', 'Pearson');
% Calcola NRMSE=> Normalizza l'errore RMSE rispetto all'intervallo dei valori del segnale originale.
NRMSE = RMSE / (max(potenze_Dominio_tagliato) - min(potenze_Dominio_tagliato));
% Calcola Relative Error=> Esprime l'errore medio relativo in percentuale.
Relative_Error = mean(abs(potenze_Dominio_tagliato - potenze_y_Misto_IDEALE) ./ potenze_Dominio_tagliato) * 100;
% Salvo le metriche
metriche(1, :) = [MAE, RMSE, R, NRMSE, Relative_Error];
metrics_table = array2table(metriche, 'VariableNames', {'MAE', 'RMSE', 'R', 'NRMSE', 'Relative_Error %'});
disp(metrics_table);

